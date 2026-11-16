//
//  OMCMessagePortListener.cpp (Linux)
//  Abracode
//
//  Linux implementation of Platform/OMCMessagePortListener.h: a Unix domain socket in the engine's
//  private folder (the port name is its path, Common/Linux/OMCDialogControlPortName.h), watched from
//  GLib's default main context, which runs on the main thread (OMC's main-thread signal and ActionUI
//  use it too). omc_dialog_control (Common/Linux/OMCDialogControlSender.c) connects, writes a 4-byte
//  length in this machine's byte order and the message, and closes; no reply.
//
//  The contract and its tests come from the probe
//  ~/git/AppleCoreLibrariesForLinux/build/probe/dialog-control-socket/REPORT.md:
//  - messages are delivered in the order their connections were accepted, one at a time; an
//    incomplete one holds back those behind it (a fast sender is never moved ahead of a slow one);
//  - every connection is read as its bytes arrive, so one waiting behind the head does not keep its
//    watch firing; a connection that ends before its message is complete is dropped;
//  - ServicePending() accepts and reads what is there now and delivers what is complete at the head;
//  - another user's connection is refused (SO_PEERCRED; the private folder already keeps others out);
//  - a socket file left by a crashed engine is removed before the bind (its name holds the dialog's UUID).
//

#include "OMCMessagePortListener.h"
#include "OMCUnixSocketAddress.h"
#include "OMCLog.h"
#include "CFObj.h"
#include <glib.h>
#include <glib-unix.h>
#include <deque>
#include <string>
#include <vector>

namespace
{

// A dialog's messages are a control's value or a table's rows; this only stops a broken sender from
// making the engine allocate without bound
const uint32_t kMaxMessageLength = 64u * 1024u * 1024u;

struct Connection
{
	int					fd { -1 };
	guint				watch { 0 };
	std::vector<UInt8>	bytes;		// the length, then the message
	size_t				have { 0 };	// bytes read so far
	size_t				need { 4 };	// 4 until the length is known, then 4 + the length
	bool				complete { false };
	bool				dead { false };	// ended or failed before its message was complete: dropped
};

class UnixSocketListener final : public OMCMessagePortListener
{
public:
							UnixSocketListener(Receive inReceive, void *inContext)
								: mReceive(inReceive), mContext(inContext)
							{
							}

							~UnixSocketListener() override
							{
								*mAlive = false;
								for(std::unique_ptr<Connection> &connection : mQueue)
									Finish(*connection);
								mQueue.clear();
								if(mListenWatch != 0)
									g_source_remove(mListenWatch);
								if(mListenFD >= 0)
									close(mListenFD);
								if(mFolderFD >= 0)
								{
									(void)unlinkat(mFolderFD, mLeaf.c_str(), 0);
									close(mFolderFD);
								}
							}

	bool					Start(CFStringRef inPortName);

	void					ServicePending() override
							{
								AcceptAll();
								ReadAll();
								DeliverReady();
							}

private:
	static gboolean			ListenerReadable(gint inFD, GIOCondition inCondition, gpointer inData);
	static gboolean			ConnectionReadable(gint inFD, GIOCondition inCondition, gpointer inData);

	void					AcceptAll();
	void					ReadAll();
	static void				ReadAvailable(Connection &ioConnection);
	static void				Finish(Connection &ioConnection);
	void					DeliverReady();

	Receive								mReceive;
	void *								mContext;
	int									mFolderFD { -1 };
	std::string							mLeaf;
	int									mListenFD { -1 };
	guint								mListenWatch { 0 };
	std::deque<std::unique_ptr<Connection>>	mQueue;		// in accept order
	bool								mDelivering { false };
	std::shared_ptr<bool>				mAlive { std::make_shared<bool>(true) };	// false once destroyed, for a receive that destroys this
};

bool
UnixSocketListener::Start(CFStringRef inPortName)
{
	std::string socketPath = OMCLogCString(inPortName);
	struct sockaddr_un address;
	const char *leaf = nullptr;
	mFolderFD = OMCMakeUnixSocketAddress(socketPath.c_str(), &address, &leaf);
	if(mFolderFD < 0)
	{
		OMCLogMessage("omc_dialog_control port: cannot use the folder of %s (errno %d)", socketPath.c_str(), errno);
		return false;
	}
	mLeaf = leaf;

	mListenFD = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	if(mListenFD < 0)
		return false;

	// A socket file left by an engine that crashed makes the bind fail; the name holds this dialog's
	// UUID and the folder is this user's private one, so whatever is there is a stale port of ours
	(void)unlinkat(mFolderFD, mLeaf.c_str(), 0);
	if( (bind(mListenFD, (struct sockaddr *)&address, sizeof(address)) != 0) ||
		(listen(mListenFD, SOMAXCONN) != 0) ) // the system maximum: senders wait here while the main thread is busy
	{
		OMCLogMessage("omc_dialog_control port: cannot listen on %s (errno %d)", socketPath.c_str(), errno);
		return false;
	}

	mListenWatch = g_unix_fd_add(mListenFD, G_IO_IN, ListenerReadable, this);
	return (mListenWatch != 0);
}

gboolean
UnixSocketListener::ListenerReadable(gint inFD, GIOCondition inCondition, gpointer inData)
{
	(void)inFD;
	(void)inCondition;
	static_cast<UnixSocketListener *>(inData)->ServicePending();
	return G_SOURCE_CONTINUE; // the listener removes this watch when it is destroyed
}

gboolean
UnixSocketListener::ConnectionReadable(gint inFD, GIOCondition inCondition, gpointer inData)
{
	(void)inFD;
	(void)inCondition;
	UnixSocketListener *listener = static_cast<UnixSocketListener *>(inData);
	listener->ReadAll();
	listener->DeliverReady();
	return G_SOURCE_CONTINUE; // a finished connection's watch is removed by Finish
}

void
UnixSocketListener::AcceptAll()
{
	if(mListenFD < 0)
		return;
	for(;;)
	{
		int fd = accept4(mListenFD, nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
		if(fd < 0)
		{
			if(errno == EINTR)
				continue;
			return; // EAGAIN: nothing more waiting
		}
		struct ucred peer;
		socklen_t peerSize = sizeof(peer);
		if( (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &peer, &peerSize) != 0) || (peer.uid != getuid()) )
		{
			close(fd);
			continue;
		}
		std::unique_ptr<Connection> connection(new Connection);
		connection->fd = fd;
		connection->bytes.resize(4);
		connection->watch = g_unix_fd_add(fd, (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR), ConnectionReadable, this);
		mQueue.push_back(std::move(connection));
	}
}

void
UnixSocketListener::ReadAll()
{
	for(std::unique_ptr<Connection> &connection : mQueue)
		ReadAvailable(*connection);
}

// Reads what has arrived; a connection that is complete or dead is finished (no watch, no descriptor)
void
UnixSocketListener::ReadAvailable(Connection &ioConnection)
{
	while( !ioConnection.complete && !ioConnection.dead && (ioConnection.fd >= 0) )
	{
		ssize_t n = read(ioConnection.fd, ioConnection.bytes.data() + ioConnection.have, ioConnection.need - ioConnection.have);
		if(n > 0)
		{
			ioConnection.have += (size_t)n;
			if( (ioConnection.need == 4) && (ioConnection.have == 4) )
			{
				uint32_t length = 0;
				memcpy(&length, ioConnection.bytes.data(), sizeof(length));
				if(length > kMaxMessageLength)
				{
					OMCLogMessage("omc_dialog_control port: a %u-byte message was refused", (unsigned)length);
					ioConnection.dead = true;
					break;
				}
				ioConnection.need = 4 + (size_t)length;
				ioConnection.bytes.resize(ioConnection.need);
			}
			if(ioConnection.have == ioConnection.need)
				ioConnection.complete = true;
			continue;
		}
		if( (n < 0) && ((errno == EAGAIN) || (errno == EWOULDBLOCK)) )
			return; // the rest has not arrived yet
		if( (n < 0) && (errno == EINTR) )
			continue;
		ioConnection.dead = true; // the sender ended or failed before its message was complete
	}
	if(ioConnection.complete || ioConnection.dead)
		Finish(ioConnection);
}

void
UnixSocketListener::Finish(Connection &ioConnection)
{
	if(ioConnection.watch != 0)
	{
		g_source_remove(ioConnection.watch);
		ioConnection.watch = 0;
	}
	if(ioConnection.fd >= 0)
	{
		close(ioConnection.fd);
		ioConnection.fd = -1;
	}
}

// Delivers complete messages from the head of the queue, in order, one at a time; stops at the first
// incomplete one. A receive may service the port again (it returns at once: one delivery at a time)
// or destroy this listener (the dialog closed): then nothing here is touched again.
void
UnixSocketListener::DeliverReady()
{
	if(mDelivering)
		return;
	mDelivering = true;
	std::weak_ptr<bool> alive(mAlive);
	while( !mQueue.empty() )
	{
		Connection &head = *mQueue.front();
		if( !head.complete && !head.dead )
			break;
		std::unique_ptr<Connection> connection = std::move(mQueue.front());
		mQueue.pop_front();
		Finish(*connection);
		if(connection->dead)
			continue;

		CFObj<CFDataRef> message( CFDataCreate(kCFAllocatorDefault, connection->bytes.data() + 4, (CFIndex)(connection->need - 4)) );
		if(message != nullptr)
			mReceive(mContext, message);
		std::shared_ptr<bool> stillAlive = alive.lock();
		if( (stillAlive == nullptr) || !*stillAlive )
			return; // destroyed by the receive; mDelivering went with it
	}
	mDelivering = false;
}

} // namespace

std::unique_ptr<OMCMessagePortListener>
OMCMessagePortListener::Create(CFStringRef inPortName, Receive inReceive, void *inContext)
{
	if( (inPortName == nullptr) || (inReceive == nullptr) )
		return nullptr;

	std::unique_ptr<UnixSocketListener> listener( new UnixSocketListener(inReceive, inContext) );
	if( !listener->Start(inPortName) )
		return nullptr;
	return listener;
}
