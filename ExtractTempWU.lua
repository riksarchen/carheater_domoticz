--Script To Parse WeatherUnderground Multi-Value Sensor, Additionally using PWS: system from WU with a new output format
--This script assumes the output (which can be viewed in events show current state button) is like this 19.5;79;3;1019;3 (temp;humidity;null;pressure;null)
--more details at this wiki http://www.domoticz.com/wiki/Virtual_weather_devices
--
--The following need updated for your environment get the 'Idx' or 'Name' off the Device tab. By default only the Temp is 'uncommented or enabled' in this script.
local sensorwu = 'Temp/Luftfuktighet/Lufttryck' --name of the sensor that gets created when you add the WU device (and that contains multiple values like temperature, humidity, barometer etc)
local idxt = 251 --idx of the virtual temperature sensor you need to change this to your own Device IDx
local idxh = 254 --idx of the virtual humidity sensor you need to change this to your own Device IDx
local idxp = 253 --idx of the virtual pressure sensor you need to change this to your own Device IDx
 
commandArray = {}
 
if devicechanged[sensorwu] then
        sWeatherTemp, sWeatherHumidity, sHumFeelsLike, sWeatherPressure = otherdevices_svalues[sensorwu]:match("([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)")
        sWeatherTemp = tonumber(sWeatherTemp)
        sWeatherHumidity = tonumber(sWeatherHumidity)
        sWeatherPressure = tonumber(sWeatherPressure)
        --parseDebug = ('WU Script Parsed Temp=' .. sWeatherTemp .. ' Humidity=' .. sWeatherHumidity .. ' Pressure=' .. sWeatherPressure)
        --print(parseDebug)
 
        commandArray[1] = {['UpdateDevice'] = idxt .. '|0|' .. sWeatherTemp}
        
        --commandArray[2] = {['UpdateDevice'] = idxh .. '|' .. tostring(sWeatherHumidity) .. '|' .. tostring(sHumFeelsLike)}
        --commandArray[3] = {['UpdateDevice'] = idxp .. '|0|' .. tostring(sWeatherPressure) .. ';' .. tostring(sWeatherPressForcast)}
end
 
return commandArray
