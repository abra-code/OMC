class OMC
{
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

	static registerElementByID(elementID)
	{
		let foundElement = document.getElementById(elementID);
		if(foundElement !== null)
		{
			foundElement.classList.add("OMC");
		}
	}

}
