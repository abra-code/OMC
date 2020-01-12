
function getAllOMCControlValues()
{
	let valuesDict = {};
	let elemsArray = document.getElementsByClassName("OMC");
	for (let i = 0, len = elemsArray.length; i < len; i++)
	{
		let elem = elemsArray[i];
		if(elem.hasAttribute('id'))
		{
			console.log("id = " + elem.id);
			if(elem.nodeName == "INPUT")
			{
				console.log("value = " + elem.value);
				valuesDict[elem.id] = elem.value;
			}
			else
			{
				console.log("innerHTML = " + elem.innerHTML);
				valuesDict[elem.id] = elem.innerHTML;
			}
		}
		
	}
	return valuesDict;
}
