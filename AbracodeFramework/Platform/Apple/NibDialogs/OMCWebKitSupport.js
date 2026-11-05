class OMC
{
	//get values of all elements whose class id = "OMC"
	static getAllElementValues()
	{
		let valuesDict = {};
		let elemsArray = document.getElementsByClassName("OMC");
		for (let i = 0, len = elemsArray.length; i < len; i++)
		{
			let elem = elemsArray[i];
			if(elem.hasAttribute('id'))
			{
				//console.log("id = " + elem.id);
				if(elem.nodeName == "INPUT")
				{
					//console.log("value = " + elem.value);
					
					if((elem.type == "checkbox") || (elem.type == "radio"))
					{
						if(elem.checked)
							valuesDict[elem.id] = elem.value;
						else
							valuesDict[elem.id] = "";
					}
					else
					{
						valuesDict[elem.id] = elem.value;
					}
				}
				else
				{
					//console.log("innerHTML = " + elem.innerHTML);
					//valuesDict[elem.id] = elem.innerHTML;
					valuesDict[elem.id] = elem.innerText;
				}
			}
		}
		return valuesDict;
	}

	//get all IDs of elements whose class id = "OMC"
	static getAllElementIDs()
	{
		var elementIDs = [];
		let elemsArray = document.getElementsByClassName("OMC");
		for (let i = 0, len = elemsArray.length; i < len; i++)
		{
			let elem = elemsArray[i];
			if(elem.hasAttribute('id'))
			{
				elementIDs.push(elem.id);
			}
		}
		return elementIDs;
	}

	//find element by id and add "OMC" class
	static registerElementByID(elementID)
	{
		let foundElement = document.getElementById(elementID);
		if(foundElement !== null)
		{
			foundElement.classList.add("OMC");
		}
	}

	//for given element assign a new id and add "OMC" class
	static registerElement(element, newID)
	{
		if(element !== undefined)
		{
			element.id = newID;
			element.classList.add("OMC");
		}
	}

	//execute command with given ID on native code side
	static execute(commandID, senderElementID)
	{
		let messageDict = {};
		if(commandID !== undefined)
		{
			messageDict["commandID"] = commandID;
			
			if (senderElementID !== undefined)
			{
				messageDict["elementID"] = senderElementID;
			}

			window.webkit.messageHandlers.OMC.postMessage(messageDict);
		}
	}
}
