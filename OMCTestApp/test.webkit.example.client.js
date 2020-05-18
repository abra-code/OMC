// This is an injected client-side JavaScript
// It is associated with OMCWebKitView instance by setting "User Define Runtime Atteribute" in nib control
// javaScriptFile=test.webkit.example.client
// This code is executed by WebKit after HTML document is loaded

function changeBackgroundColor(inColor)
{
	document.body.style.backgroundColor = inColor;
}

changeBackgroundColor("teal");

// OMC injects OMCWebKitSupport.js before document load and adds OMC APIs:
// OMC.getAllElementValues()
// OMC.getAllElementIDs()
// OMC.registerElementByID(elementID)
// OMC.registerElement(element, newID)
// OMC.execute(commandID, senderElementID)

// If you don't control the HTML to assign class="OMC" to elements, you can register them dynamically
// Registering elements with OMC makes their values visible as env variables in executed scripts in form:
// OMC_NIB_WEBVIEW_N_ELEMENT_XYZ_VALUE
// where N is OMCWebKitView control tag/id in nib dialog and
// XYZ is HTML element ID, normalized by capitalization and replacing non-alphanumeric characters with _
// for example OMC_NIB_WEBVIEW_2_ELEMENT_ONE_VALUE below

OMC.registerElementByID("one");
OMC.registerElementByID("two");

// Now register an element without an initial id in HTML
// OMC requires IDs for elements to get their values
// so when you call OMC.registerElement(element, newID)
// you are assigning a new ID, potentially overwriting an existing one
// this of course might have unexpected side effects if some other code relies on previous ID
let depthElems = document.getElementsByClassName("depth");
if(depthElems.length == 1)
{
	OMC.registerElement(depthElems[0], "three");
}

// Add event listener to elements to execute an OMC command on native side
// any element can trigegr commands that way, it does not need to be of class OMC
function excuteOMCCommandOnClick()
{
	const commandID = "test.webkitview.clicked";
	let senderElementID = this.id;
	OMC.execute(commandID, senderElementID);
}

let elementFireCheckbox = document.getElementById("fire");
elementFireCheckbox.addEventListener("click", excuteOMCCommandOnClick, false);

let elementTwo = document.getElementById("two");
elementTwo.addEventListener("dblclick", excuteOMCCommandOnClick, false);

// This one has the id dynamically assigned by OMC.registerElement()
// so let's test if we can actually find it by its new id
let elementThree = document.getElementById("three");
elementThree.addEventListener("mouseup", excuteOMCCommandOnClick, false);

