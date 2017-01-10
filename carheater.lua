-- USERINPUTS REQUIRED
local nSensortemp                   = '<YOUR TEMP SENSOR>'                               -- name of your outside temperature sensor
local nMotorswitch                  = '<YOUR RELAY>'                         -- name of the relayswitch
local nUsageswitch                  = '<YOUR RELAYs USAGE'                     -- name of the usage sensor
local device_idx                    = '<YOUR IDX>'                                         -- INPUT YOUR IDX of the GCal Device switch

-- USERSETTINGS
local udebug                        = false                                         -- debugging 
local umaxTempAllowed               = 8                                             -- disable carheater if temperature is above
local umaxTimeLogic                 = 180                                           -- maximum number of minutes the sTemp logic will return
local ubaseTimeLogic                = 60                                            -- adjust this time if the car is to warm or to cold
local uautoPowerOff_noUsage         = true                                          -- enable/disable automatic shutoff if usage = 0 Watt
local umaxTimeNoUsage               = 10                                            -- minutes with no usage before the relay is shutoff
local uautoPowerOff_wUsage          = true                                          -- enable/disable automatic shutoff after x minutes (both timer and manual start)
local umaxTimewUsage                = 300                                           -- shutoff relay after x minutes with usage > 0 Watt. Cannot be less than umaxTimeLogic 

-- ##########################################################
-- #            END OF USERSETTINGS                         #
-- ##########################################################

-- functions
function timedifference (s, t)
  year = string.sub(s, 1, 4)
  month = string.sub(s, 6, 7)
  day = string.sub(s, 9, 10)
  hour = string.sub(s, 12, 13)
  minutes = string.sub(s, 15, 16)
  seconds = string.sub(s, 18, 19)
  t1 = t
  t2 = os.time{year=year, month=month, day=day, hour=hour, min=minutes, sec=seconds}
  difference2 = os.difftime (t1, t2)
  return difference2
end

function RunTime (s)
    if s > umaxTempAllowed then 
        runningtime = 0 
        return runningtime
    end
    runningtime = (s / 10 * -60) + ubaseTimeLogic
    if runningtime > umaxTimeLogic then runningtime = umaxTimeLogic end
    if runningtime < 0 then runningtime = 0 end
    return runningtime * 60
end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

commandArray = {}

-- variables
local vTimezerousage                = 'Timer'..device_idx..'NoUsageTime'            -- Time when zero usage was sensed
local vTimerLastRun                 = 'Timer'..device_idx..'Run'                    -- Time when timer turned on carheater last time
local vGCaltimeStart                = 'GCal'..device_idx..'NextStart'               -- Next event from google calender (leavetime)
local vGCaltimeStop                 = 'GCal'..device_idx..'NextStop'                -- Next event ending time (ending time for carheater)

-- values
local tNow                          = os.time()
local sTemp                         = tonumber(otherdevices[nSensortemp])
local carheater_runtime             = RunTime(sTemp)
local tGCalStart                    = uservariables[vGCaltimeStart]
local tGCalStop                     = uservariables[vGCaltimeStop]
local tLastRun                      = tNow - uservariables[vTimerLastRun]
local tlStart                       = tNow - tGCalStart + carheater_runtime
local tlStop                        = tNow - tGCalStop
local tlNoUsageSwitch               = timedifference(otherdevices_lastupdate[nMotorswitch], tNow) - (umaxTimeNoUsage * 60)
local tlNoUsageSensor               = tNow - uservariables[vTimezerousage] - (umaxTimeNoUsage * 60)
local tlUsageSwitch                 = timedifference(otherdevices_lastupdate[nMotorswitch], tNow) - (umaxTimewUsage * 60)

-- uautoPowerOff_noUsage
if (uautoPowerOff_noUsage and otherdevices[nMotorswitch] == 'On') then 
    -- UPDATE USERVARIABLE WITH LAST TIME USAGE = 0
    if (devicechanged[nUsageswitch]) then
        if (tonumber(otherdevices_svalues[nUsageswitch]) == 0) then
            if (uservariables[vTimezerousage] == 0) then
                commandArray['Variable:' .. vTimezerousage] = tostring(os.time())
            end
        elseif (uservariables[vTimezerousage] > 0) then
            commandArray['Variable:' .. vTimezerousage] = '0'
        end
    end

    -- CHECK IF TIME WITH 0 USAGE IS LONGER THAN ALLOWED
    if (tonumber(otherdevices_svalues[nUsageswitch]) == 0 and tlNoUsageSwitch >= 0 and tlNoUsageSensor >= 0 and sTemp <= umaxTempAllowed) then
        if (uservariables[vTimezerousage] == 0) then 
            ptimeNoPower = round(timedifference(otherdevices_lastupdate[nMotorswitch], tNow) / 60, 0)
        else
            ptimeNoPower = round((tNow - uservariables[vTimezerousage]) / 60, 0)
        end

        print("Slår av " .. nMotorswitch .. ", ingen Strömförbrukning senaste " ..  ptimeNoPower .. " min.")
        --commandArray['SendNotification']='Motorvärmare avslagen!#'..nMotorswitch..' har varit påslagen utan strömförbrukning i ' .. ptimeNoPower .. ' minuter. Stänger av!#0'
        commandArray[nMotorswitch] = 'Off'
    end
end

-- uautoPowerOff_wUsage
if (uautoPowerOff_wUsage and otherdevices[nMotorswitch] == 'On') then
    if (sTemp < umaxTempAllowed and tlUsageSwitch >= 0 and tonumber(otherdevices_svalues[nUsageswitch]) > 0) then
        print("Slår av " .. nMotorswitch .. ", Max tillåten körtid är " ..  umaxTimewUsage .. " min.")
        commandArray['SendNotification']='Motorvärmare avslagen!#'..nMotorswitch..' har gått längre än tillåten gångtid. Stänger av!#0'
        commandArray[nMotorswitch] = 'Off'
    end
end

-- carheater start
if (udebug) then
    print(tGCalStart.." > 0 == tGCalStart")
    print(tlStart.." >= 0 == tlStart")
    print(tlStart.." < "..tLastRun.. " == tlStart < tLastRun")
    print("tLastRun timeformat: "..os.date("%c", tLastRun))
    print("nMotorswitch == 'Off': "..otherdevices[nMotorswitch])
    print(carheater_runtime.. " > 0 == carheater_runtime > 0: ")
    print("time: "..os.time())
end
        
if (tGCalStart > 0 and tlStart >= 0 and tlStart < tLastRun) then
    if (otherdevices[nMotorswitch] == 'Off') then
        if (carheater_runtime > 0) then
            local switchOnfor = round(tlStop / -60, 0)
            print("Startar " .. nMotorswitch .. " i " .. switchOnfor .. " minuter, utetemperatur är " .. sTemp .. " celcius.")
            commandArray[nMotorswitch] = 'On FOR ' .. switchOnfor
            commandArray['Variable:' .. vTimerLastRun] = tostring(os.time())
        else
            print("Startar inte " .. nMotorswitch .. ", utetemperatur är " .. sTemp .. " celcius.")
        end
    else
        print(nMotorswitch .. " är redan på. Manuell avstängning krävs. Utetemperatur är " .. sTemp .. " celcius.")
        commandArray['Variable:' .. vTimerLastRun] = tostring(os.time())
    end
end

-- debugging
if (udebug) then
    print(nMotorswitch .. " relay: " .. otherdevices[nMotorswitch])
    print("Last timer run: " .. os.date("%c", uservariables[vTimerLastRun]))
    print("Leavingtime from google cal: " .. os.date("%c", tGCalStart))
    print("Endtime from google cal: " .. os.date("%c", tGCalStop))
    print("carheater starting: " .. os.date("%c", tNow - tlStart))
    print("carheater stop at: " .. os.date("%c", tNow - tlStop))
    print("Automatic shutoff if usage = 0: " .. tostring(uautoPowerOff_noUsage))
    print("Automatic shutoff if usage > 0: " .. tostring(uautoPowerOff_wUsage))
    print("Automatic shutoff if usage = 0 after: " .. tostring(umaxTimeNoUsage) .. " minutes.")
    print("Automatic shutoff if usage > 0 after: " .. umaxTimewUsage .. " minutes.")
    print("Current time is: " .. os.date("%X", tNow))
    print("Outside temperature: " .. sTemp .. " celcius.")
end
return commandArray
