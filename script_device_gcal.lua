-----------------------------------------------------------------------------
--	script_device_gcal.lua: A Google Calendar script aimed for Domoticz
--	Author: BakSeeDa (à¸šà¸±à¸à¸ªà¸µà¸”à¸²)
--	Homepage: https://www.domoticz.com/forum/memberlist.php?mode=viewprofile&u=7064
--
--	CREDITS:
--		This project was originally developed as a plugin for the Vera
--		(Micasaverde) controller by Stuart.
--		See http://forum.micasaverde.com/index.php/topic,26692.0.html

-----------------------------------------------------------------------------
--	I will ask Stuart if this software can be published under the
--	GNU General Public License or not
-----------------------------------------------------------------------------
--
--	REQUIREMENTS:
--		Domoticz running on Raspberry Pi or Synology.
--		bakseeda.lua
--
local GCAL_VERSION = "V 1.0.2"  
--	CHANGELOG
--		1.0.2 New location of the credentials folder for Synology systems.
--					Better detection of path for Domoticz install directory and script directory.
--					Setting the package.path before including files using "require" for
--					improved compatibility.
--		1.0.1 Removed the check for openssl since the command differ on different unix systems.
--					Added CalendarID as part of the json Events file name to allow multiple instances.
--					Fixed so that the events.json file is written using valid json syntax.
--		1.0.0 Finally got out of beta status.
--					Fixed: Text device did not update if authentication used on Domoticz.
--		0.1.4 Corrected so that the preferred debug level always is fetched from the user variables.
--		0.1.3	Changed so that calendar data refreshes using a time script instead.
--		0.1.2	Introduced separate "at" queues for each calendar.
--		0.1.1	Fixed format when no more events were found.
--					Corrected the version displayed in debug messages.
--		0.1.0	Added this information header.
-----------------------------------------------------------------------------

commandArray = {}

function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

local scriptDir = script_path()
package.path = scriptDir.."?.lua;"..package.path
local domoDir = scriptDir:gsub("scripts%/lua%/", "")

--print(scriptDir)
--print(domoDir)

local gcalconfig = require("gcalconfig")
local myGCalDevs = gcalconfig.GCalDevs

local i, iGCal = nil
for i=1, #myGCalDevs.checkSwitches.names do
	if (devicechanged[myGCalDevs.checkSwitches.names[i]] == 'On') then
		iGCal = i
		break
	end
end

if (iGCal ~= nil) then
	local b = require("bakseeda")
	local GC = {}
	GC.CalendarID = ""

	GC.plugin_name = "GCal3" -- Do not change for this plugin

	-- No comments for you, it was hard to write, so it should be hard to read.
	GC.basepath = domoDir -- On Rpi: /home/pi/domoticz/
	GC.luascriptpath = scriptDir -- On RPi: /home/pi/domoticz/scripts/lua/
	GC.pluginpath = GC.basepath .. GC.plugin_name .."/" -- putting some files in a sub directory to keep things uncluttered
	GC.jsonlua = GC.luascriptpath .. "json.lua"
	GC.credentialfile = GC.plugin_name .. ".json" -- the service account credential file downloaded from google developer console
	GC.pemfile = GC.pluginpath .. GC.plugin_name ..".pem" -- certificate to this file
	GC.semfile = GC.pluginpath .. GC.plugin_name ..".sem" -- semaphore file  

	-- Main plugin Variables
	GC.timeZone = 0
	GC.timeZonehr = 0
	GC.timeZonemin = 0
	GC.now = os.time()
	GC.utc = 0
	GC.startofDay = 0
	GC.endofDay = 0
	GC.Events = {}
	GC.nextTimeCheck = os.time()
	GC.trippedID = ""
	GC.trippedEvent = ""
	GC.trippedStatus = 0
	GC.trippedIndex = 0
	GC.retrip = "true"
	GC.retripTemp = "true"
	b.debug = 3
	b.debugPre = "GCal3 "..GCAL_VERSION
	GC.Keyword = ""
	GC.ignoreKeyword = "false"
	GC.exactKeyword = "true"
	GC.triggerNoKeyword = "false"
	GC.ignoreAllDayEvent = "false"
	GC.StartDelta = 0
	GC.EndDelta = 0
	GC.CalendarID = ""
	GC.iCal = false
	GC.access_token = ""
	GC.access_error = 0
	GC.allowEventAdd = true
	GC.nextCheckutc = ""  -- string Time of next check for calendar in utc time
	GC.allowCalendarUpdate = true
	-- I have to find a better job
	
	local function osExecute(command) 
		local result = os.execute(command)
		b.DEBUG(3,"Command " .. command .. " returned " ..tostring(result))
		return result
	end

	local function upperCase(str)
		str = string.upper(str)
		local minusChars={"Ã ","Ã¡","Ã¢","Ã£","Ã¤","Ã¥","Ã¦","Ã§","Ã¨","Ã©","Ãª","Ã«","Ã¬","Ã­","Ã®","Ã¯","Ã°","Ã±","Ã²","Ã³","Ã´","Ãµ","Ã¶","Ã·","Ã¸","Ã¹","Ãº","Ã»","Ã¼","Ã½","Ã¾","Ã¿"}
		local majusChars={"Ã€","Ã","Ã‚","Ãƒ","Ã„","Ã…","Ã†","Ã‡","Ãˆ","Ã‰","ÃŠ","Ã‹","ÃŒ","Ã","ÃŽ","Ã","Ã","Ã‘","Ã’","Ã“","Ã”","Ã•","Ã–","Ã·","Ã˜","Ã™","Ãš","Ã›","Ãœ","Ã","Ãž","ÃŸ"}
		for i = 1, #minusChars, 1 do
			str = string.gsub(str, minusChars[i], majusChars[i])
		end
		return str 
	end

	local function trimString( s )
		return string.match( s,"^()%s*$") and "" or string.match(s,"^%s*(.*%S)" )
	end

	local function strToTime(s) -- assumes utc drops seconds
		local _,_,year,month,day = string.find(s, "(%d+)-(%d+)-(%d+)")
		local _,_,hour,minute,_ = string.find(s, "(%d+):(%d+):(%d+)")
		if (hour == nil) then -- an all-day event has no time component so adjust to utc
			hour = - GC.timeZonehr
			minute = - GC.timeZonemin
			-- second = 0
		end
		return os.time({isdst=os.date("*t").isdst,year=year,month=month,day=day,hour=hour,min=minute,sec=0})
	end

	local function compare(a,b) -- used for sorting a table by the first column
		return a[1] < b[1]
	end

	local function strLocaltostrUTC(s)
		local utc = strToTime(s)
		utc = utc - GC.timeZone
		local ta = os.date("*t",utc)
		return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", ta.year, ta.month, ta.day, ta.hour, ta.min, 0)
	end

	-- system, file i/o and related local functions

	local function os_command (command) 
	 local stdout = io.popen(command)
			local result = stdout:read("*a")
			stdout:close()
	 return result
	end

	local function readfromfile(filename)
		local result = osExecute("/bin/ls " .. filename) -- does the file exist  
		if (result ~= nil and result ~= true) then -- return since we cannot read the file
			b.setVar("GCal"..GC.device_idx.."NextEvent",string.gsub(filename,"/(.*)/",""), 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime","Could not Open" , 2)
			return nil
		end
		
		local f = io.open(filename, "r")
		if not f then return nil end
		local c = f:read "*a"
		f:close()
		return c
	end

	local function writetofile (filename,package)
		local f = assert(io.open(filename, "w"))
		local t = f:write(package)
		f:close()
		--return t    
		-- t doesn't seem to return anything useful, I might be wrong but let's try to read the file
		--print("Hello")
		f = io.open(filename, "r")
		if not f then return false end
		local c = f:read "*a"
		f:close()
		if (tostring(c) == tostring(package)) then return true else return false end
	end

	-- Authorization related local functions

	local function checkforcredentials(json)
		b.DEBUG(3,"local function: checkforcredentials")

		--make sure we have a credentials file
		result = osExecute("/bin/ls " .. GC.pluginpath .. GC.credentialfile) -- check to see if there is a file
		if not result then -- we don't have a credential file
			b.DEBUG(3,"Could not find the credentials file: " .. GC.pluginpath .. GC.credentialfile)
			return nil
		end
		
		local contents = readfromfile(GC.pluginpath .. GC.credentialfile)
			
		if (not string.find(contents, '"type": "service_account"')) then
			b.DEBUG(3,"The credentials are not for a service account")
			return nil
		end
		if (not string.find(contents, '"private_key":')) then
			b.DEBUG(3,"The credentials file does not contain a private key")
			return nil
		end
		if (not string.find(contents, '"client_email":')) then
			b.DEBUG(3,"The credentials file does not contain a client email")
			return nil
		end
		
		local credentials = json.decode(contents)

		-- Delete the PEM file if it's older than the credentialfile 
		osExecute("find " .. GC.pluginpath .. " -type f ! -newer " .. GC.credentialfile .. " -name " .. GC.plugin_name ..".pem" .. " -delete")
		
		--create the pem file if it doesn't exist
		result = osExecute("/bin/ls " .. GC.pemfile) -- check to see if there is a file
		if not result then -- Go ahead and create the pem file
			local pem = credentials.private_key
			local result = osExecute("/bin/rm -f ".. GC.pemfile) -- Are we sure it's gone?
			result = writetofile (GC.pemfile,pem) -- create the new one
			b.DEBUG(3,"New PEM file created")
			if not result then
				b.DEBUG(3,"Could not create the file - " .. GC.pemfile)
				return nil
			end
		end

		 -- get the service account email name 
		GC.ClientEmail = credentials.client_email
		return true
	end

	local function get_access_token(json)
		b.DEBUG(3, "local function: get_access_token")
		-- First check to see if we have an existing unexpired token
		GC.access_token = GC.access_token or ""
		if (GC.access_token ~= "") then
			b.DEBUG(3, "Trying to verify the existing access token. " .. GC.access_token)
			local body = b.runcommand('curl -v -H "Content-Type:application/json" -H "Accept: application/json" https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=' .. GC.access_token)
			-- b.DEBUG(2,"Token info body: " .. body)
			if ((string.find(body,'{')) and not (string.find(body,'error'))) then
				local tokencheck = json.decode(body)
				local time_to_expire = tokencheck.expires_in
				b.DEBUG(2,"Token will expire in " .. time_to_expire .." sec")
				if (time_to_expire > 10) then -- 10 seconds gives us some leeway
					return GC.access_token -- the current token was still valid
				end
			else
				b.DEBUG(3, "Could not verify the existing access token")
				return nil
			end
		end

		b.DEBUG(2,"Getting a new token")
		-- get a new token  
		local str = '\'{"alg":"RS256","typ":"JWT"}\''
		local command = "echo -n " .. str .. " | openssl base64 -e"		
		local jwt1= os_command(command)
		if not jwt1 then
			b.DEBUG(3,"Error encoding jwt1")
		return nil
		end
		jwt1 = string.gsub(jwt1,"\n","")

		local iss = GC.ClientEmail 
		local scope = "https://www.googleapis.com/auth/calendar"
		local aud = "https://accounts.google.com/o/oauth2/token"
		local exp = tostring(os.time() + 3600)
		local iat = tostring(os.time())
	 
		str = '\'{"iss":"' .. iss .. '","scope":"' .. scope .. '","aud":"' .. aud .. '","exp":' .. exp .. ', "iat":' .. iat .. '}\''
		command = "echo -n " .. str .. " | openssl base64 -e"
		local jwt2 = os_command(command)
		if not jwt2 then
			b.DEBUG(3,"Error encoding jwt2")
		return nil
		end
		jwt2 = string.gsub(jwt2,"\n","")
	 
		local jwt3 = jwt1 .. "." .. jwt2
		jwt3 = string.gsub(jwt3,"\n","")
		jwt3 = string.gsub(jwt3,"=","")
		jwt3 = string.gsub(jwt3,"/","_")
		jwt3 = string.gsub(jwt3,"%+","-")
		command ="echo -n " .. jwt3 .. " | openssl sha -sha256 -sign " .. GC.pemfile .. " | openssl base64 -e"
		local jwt4 = os_command(command)
		if not jwt4 then
			b.DEBUG(3,"Error encoding jwt4")
		return nil  
		end
		jwt4 = string.gsub(jwt4,"\n","")
	 
		local jwt5 = string.gsub(jwt4,"\n","")
		jwt5 = string.gsub(jwt5,"=","")
		jwt5 = string.gsub(jwt5,"/","_")
		jwt5 = string.gsub(jwt5,"%+","-")
		command = "curl -k -s -H " .. '"Content-type: application/x-www-form-urlencoded"' .. " -X POST " ..'"https://accounts.google.com/o/oauth2/token"' .. " -d " .. '"grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=' .. jwt3 .. "." .. jwt5 ..'"'
		
		local token = os_command(command)
		if not token then
			b.DEBUG(3,"Error getting token")
			return nil
		end
	 
		if (string.find(token, '"error"')) then
			b.DEBUG(3,"The token request returned an error: " .. token)
			return nil
		end
	 
		if (not string.find(token, '\"access_token\" :')) then
			b.DEBUG(3,"The token request did not provide an access token: " .. token)
			return nil
		end
		b.DEBUG(2,"Got new token")
		local jsontoken = json.decode(token)
		return jsontoken.access_token 
	end

	-- plugin specifc local functions
	local function releaseSemaphore(s)
		local _ = writetofile(GC.semfile,"0") -- release the semaphore
		b.DEBUG(1,"Device " .. GC.device_idx .. " released the semaphore - reason: " .. s)
	end

	local function getSemaphore()
		-- to avoid race conditions if there are multiple plugin instances
		-- we set set up a semaphore using a file
		-- return true if semaphore claimed, false if not
		b.DEBUG(3,"Checking semaphore")
		local contents = tostring(readfromfile(GC.semfile))
		b.DEBUG(3,"Semaphore file returned " .. (contents or "nil"))
		if ((contents == "0") or (contents == "nil")) then -- noone holds the semaphore
			local result = writetofile(GC.semfile,GC.device_idx) -- try to claim it
			if not result then
				b.DEBUG(3,"Could not create the file - " .. GC.semfile)
			return false
			end
			b.DEBUG(2,"Device " .. GC.device_idx .. " requested semaphore")
		end
		
		contents = tostring(readfromfile(GC.semfile))
		if (contents == GC.device_idx) then -- successfully claimed
			b.DEBUG(1,"Device " .. GC.device_idx .. " claimed semaphore")
			return true
		end
		b.DEBUG(3,"Device " .. contents .. " blocked semaphore request from device " .. GC.device_idx)
		return false
	end

	local function getStartMinMax(startdelta,enddelta)
		local s1, s2, s3 = "","",""
		-- startmin and startmax use utc but startmin must be at least start of today local time
		local starttime, endofday, endtime = GC.now, GC.now, GC.now
		--local endofday = starttime
		local ta = os.date("*t", starttime)
		s1 = string.format("%d-%02d-%02dT%02d:%02d:%02d", ta.year, ta.month, ta.day, 00, 00, 00)
		starttime = strToTime(s1)
		ta = os.date("*t", starttime + 24 * 3600)
		s3 = string.format("%d-%02d-%02dT%02d:%02d:%02d", ta.year, ta.month, ta.day, 23, 59, 59)
		endofday = strToTime(s3)
		GC.startofDay = starttime - GC.timeZone
		GC.endofDay = endofday - GC.timeZone

		-- startmax look forward 24 hrs
		endtime = endtime + (3600*24)

		-- adjust fo any start and end delta
		if (startdelta < 0) then -- look back further in time
			starttime=starttime - (startdelta * 60)
		end
		if (enddelta >= 0) then -- look forward further in time
			endtime = endtime + (enddelta * 60)
		end

		ta = os.date("*t", starttime)
		s1 = string.format("%d-%02d-%02dT%02d:%02d:%02d.000", ta.year, ta.month, ta.day, ta.hour, ta.min, ta.sec)
		s1 = strLocaltostrUTC(s1)
		ta = os.date("*t", endtime)
		s2 = string.format("%d-%02d-%02dT%02d:%02d:%02d.000", ta.year, ta.month, ta.day, ta.hour, ta.min, ta.sec)
		s2 = strLocaltostrUTC(s2)
		b.DEBUG(3,"StartMin is " .. s1 .. " StartMax is " .. s2)
		b.DEBUG(3,"End of day is " .. s3)
		return s1, s2 -- in utc
	end

	local function formatDate(line) -- used to interpret ical
		local _,_,year,month,day = string.find(line,":(%d%d%d%d)(%d%d)(%d%d)") -- get the date
		local datetime = year .. "-" .. month .. "-" .. day -- format for google
		local _,_,hour,min,sec = string.find(line,"T(%d%d)(%d%d)(%d%d)Z")
		if (hour ~= nil) then -- time was specified in utc
			datetime = datetime .. "T" .. hour .. ":" .. min .. ":" .. sec .. "Z"
		else -- date and time are local and need to be converted to utc
			local _,_,hour,min,sec = string.find(line,"T(%d%d)(%d%d)(%d%d)")
			if (hour ~= nil) then -- this is a local time format and needs to be converted to utc
				datetime = datetime .. "T" .. hour .. ":" .. min .. ":" .. sec
				datetime = strLocaltostrUTC(datetime)
			end
		end
		return datetime
	end


	local function requestiCalendar(startmin, startmax)
		b.DEBUG(3,"local function: requestiCalendar")
		startmin = string.gsub(startmin,"%.000Z","Z")
		local startminTime = strToTime(startmin)
		startmax = string.gsub(startmax,"%.000Z","Z")
		local startmaxTime = strToTime(startmax)

		if (GC.CalendarID == nil) then
			b.DEBUG(3,"Calendar ID is not set.")
			b.setVar("GCal"..GC.device_idx.."NextEvent","Missing Calendar ID", 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime","." , 2)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
			return nil
		end

		b.DEBUG(2,"Checking iCal calendar")
			 
		local url = GC.CalendarID
		
		b.setVar("GCal"..GC.device_idx.."NextEvent","Accessing iCal", 2)
		b.setVar("GCal"..GC.device_idx.."NextEventTime","." , 2)
		b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
		b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)

		--b.DEBUG(3,"Requested url: " .. url)
	 
		--local body,code,_ , status = https.request(url) -- get the calendar data
		local body = b.runcommand('curl -v "' .. url ..'"')
		-- b.DEBUG(2,"Token info body: " .. body)
		if (not string.find(body,'BEGIN:VCALENDAR')) then
			b.DEBUG(1, "Error getting icalendar data: " .. body)
			b.setVar("GCal"..GC.device_idx.."NextEvent", "Error while getting icalendar data" , 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
			return nil
		end		
		
		local ical, icalevent = {}
		local eventStart, eventEnd, eventName, eventDescription = ""
		local inEvent = false
		-- Parse the iCal data
		b.setVar("GCal"..GC.device_idx.."NextEvent","Start Parsing iCal", 2)
		for line in body:gmatch("(.-)[\r\n]+") do

			if line:match("^BEGIN:VCALENDAR") then b.DEBUG(3,"Start parsing iCal") end
			if line:match("^END:VCALENDAR") then b.DEBUG(3,"End parsing iCal") end
			if line:match("^BEGIN:VEVENT") then
				 icalevent = {}
				 eventStart, eventEnd, eventName, eventDescription = ""
				 inEvent = true
				 b.DEBUG(3,"Found iCal event")
			end
			if (inEvent == true) then
				if line:match("^DTEND") then eventEnd = formatDate(line); b.DEBUG(3,"iCal Event End is : " .. eventEnd) end
				if line:match("^DTSTART") then eventStart = formatDate(line); b.DEBUG(3,"iCal Event Start is : " .. eventStart) end
				if line:match("^SUMMARY") then _,_,eventName = string.find(line,":(.-)$") end
				if line:match("^DESCRIPTION") then _,_,eventDescription = string.find(line,":(.*)$") end -- only gets one line     
				if line:match("^END:VEVENT") then
					inEvent = false
					if ((strToTime(eventStart) >= startminTime) and (strToTime(eventStart) <= startmaxTime)) then
						if string.find(eventStart,"T") then -- not an all day event
							icalevent = {["start"] = {["dateTime"] = eventStart},["end"] = {["dateTime"] = eventEnd},["summary"] = eventName,["description"] = eventDescription}
						else
						 icalevent = {["start"] = {["date"] = eventStart},["end"] = {["date"] = eventEnd},["summary"] = eventName,["description"] = eventDescription}
						end 
						table.insert(ical, icalevent)
					end
				end
			end
		end
		
		if (#ical == 0) then
			b.DEBUG(1,"No iCal events found. Retry later")
			b.setVar("GCal"..GC.device_idx.."NextEvent","No iCal events found today" , 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime",".", 2)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
			b.setVar("GCal"..GC.device_idx.."EventsToday",0, 0)
			b.setVar("GCal"..GC.device_idx.."EventsLeftToday", 0, 0)
			local _ = setTrippedOff(GC.trippedStatus)
			return "No Events"
		else
			b.setVar("GCal"..GC.device_idx.."NextEvent","Found " .. #ical .. " iCal events", 2)
			return ical
		end
	end

	local function requestCalendar(startmin, startmax, json)
		b.DEBUG(3,"local function: requestCalendar")

		if (GC.CalendarID == nil) then
			b.DEBUG(3,"Calendar ID is not set.")
			b.setVar("GCal"..GC.device_idx.."NextEvent","Missing Calendar ID", 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime","." , 2)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			return nil
		end
	 
		GC.access_token = get_access_token (json)
		if GC.access_token == nil then
			b.setVar("GCal"..GC.device_idx.."NextEvent","Fatal error - access token", 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime","." , 2)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
			b.DEBUG(1,"Fatal error trying to get access token")
			GC.access_token = ""  -- reset the token default
		return nil
		end
	 
		b.DEBUG(2,"Checking google calendar")
			 
		local url = "https://www.googleapis.com/calendar/v3/calendars/".. GC.CalendarID .. "/events?"
		url = url .. "access_token=" .. GC.access_token .. "&timeZone=utc"
		url = url .. "&singleEvents=true&orderBy=startTime"
		url = url .. "&timeMax=" .. startmax .. "&timeMin=" .. startmin
		url = url .. "&fields=items(description%2Cend%2Cstart%2Csummary)"
		
		b.setVar("GCal"..GC.device_idx.."NextEvent","Accessing Calendar", 2)
		b.setVar("GCal"..GC.device_idx.."NextEventTime","." , 2)
		b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
		
		--b.DEBUG(3,"Requested url: " .. url)
		--local body,code,_,status = https.request(url) -- get the calendar data

		local body = b.runcommand('curl -v -H "Content-Type:application/json" -H "Accept: application/json" "' .. url ..'"')
		-- b.DEBUG(2,"Token info body: " .. body)
		if ((not string.find(body,'{')) or (string.find(body,'error'))) then
			b.DEBUG(1, "Error getting calendar data: " .. body)
			b.setVar("GCal"..GC.device_idx.."NextEvent", "Error while getting calendar data" , 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
			return nil
		end

		-- make sure we have well formed json
		local goodjson = string.find(body, "items")
		if (not goodjson) then
			b.DEBUG(1,"Calendar data problem - no items tag. Retry later...")
			b.setVar("GCal"..GC.device_idx.."NextEvent", "Bad Calendar data" , 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
			return nil 
		end

		local noitems = string.find(body, '%"items%"%:% %[%]') -- empty items array
		if (noitems) then
			b.DEBUG(1,"No event in the next day. Retry later...")
			b.setVar("GCal"..GC.device_idx.."NextEvent", '<span style="color: grey;">No events found today</span>', 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
			b.setVar("GCal"..GC.device_idx.."EventsToday", 0, 0)
			b.setVar("GCal"..GC.device_idx.."EventsLeftToday", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
			local _ = setTrippedOff(GC.trippedStatus)
			return "No Events" 
		end


		-- decode the calendar info
		local json_root = json.decode(body)
	 
		local events = json_root.items

		if (events[1] == nil) then
			b.DEBUG(1,"Nil event in the next day. Retry later...")
			b.setVar("GCal"..GC.device_idx.."NextEvent", "Nil events found today", 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
			b.setVar("GCal"..GC.device_idx.."EventsToday", 0, 0)
			b.setVar("GCal"..GC.device_idx.."EventsLeftToday", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
			b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
			local _ = setTrippedOff(GC.trippedStatus)
			return "No Events"
		end
		b.setVar("GCal"..GC.device_idx.."NextEvent","Calendar Access Success", 2)
		b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
		b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
		b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
		return events -- an table of calendar events
	end

	local function allDay(start)
		-- Get the start time for the event
		local _,_,esHour,_,_ = string.find(start, "(%d+):(%d+):(%d+)")
		local allDayEvent
		if (esHour == nil) then -- an all day event has no hour component
			allDayEvent = os.date("%d %b", strToTime(start))
		else
			allDayEvent = ""
		end
		return allDayEvent
	end

	local function saveEvents(json)
		b.DEBUG(3,"local function: saveEvents")
		local eventsJson = {}
		local jsonEvents = {}
		local activeEventsJson = {}
		local jsonActiveEvents = {}
		local numberEvents = #GC.Events
		
		if numberEvents == 0 then
			--b.setVar("GCal"..GC.device_idx.."jsonEvents","[]", 2)
			osExecute('echo "[]" >' .. GC.jsonEventsfile .. "&&chmod 744 " .. GC.jsonEventsfile)
			b.setVar("GCal"..GC.device_idx.."jsonActiveEvents","[]", 2)
			b.setVar("GCal"..GC.device_idx.."ActiveEvents","", 2)
			return
		end
		
		for i = 1,numberEvents do
			-- convert datetime to local time for easier use by others
			jsonEvents = {["eventStart"] = (GC.Events[i][1] + GC.timeZone),["eventEnd"] = (GC.Events[i][2] + GC.timeZone),["eventName"] = GC.Events[i][3],["eventParameter"] = GC.Events[i][4]}
			table.insert(eventsJson, jsonEvents)
		end
		
		local ActiveEvents = ""
		local eventtitle = ""
		local eventparameter = ""
		
		for i = 1,numberEvents do
			if ((GC.Events[i][1] <= GC.utc) and (GC.utc < GC.Events[i][2])) then -- we are inside the event
				eventtitle = GC.Events[i][3]
				eventparameter = GC.Events[i][4]
				if (ActiveEvents == "" ) then
					ActiveEvents = eventtitle
				else  
					ActiveEvents = ActiveEvents .. " , " .. eventtitle
				end
				jsonActiveEvents = {["eventName"] = eventtitle,["eventParameter"] = eventparameter}
				table.insert(activeEventsJson, jsonActiveEvents)
			end
		end
		
		b.setVar("GCal"..GC.device_idx.."ActiveEvents", ActiveEvents, 2)
		b.DEBUG(3, "Active Events: " .. ActiveEvents)
		 
		local eventList =json.encode(eventsJson) -- encode the table for storage as a string
		--print("eventList: " .. eventList)
		
		-- This eventlist string is to large to store in a user variable, let's dump it into a file.
		local file = io.open(GC.jsonEventsfile, "w")
		file:write(eventList)
		file:close()
		osExecute("chmod 644 " .. GC.jsonEventsfile)

		--b.DEBUG(3,"json event list " .. eventList)

		eventList =json.encode(activeEventsJson) -- encode the table for storage as a string

		b.setVar("GCal"..GC.device_idx.."jsonActiveEvents", eventList, 2)
		b.DEBUG(2,"json active event list " .. eventList)
		
		return
	end

	-- ***********************************************************
	-- This local function extracts the events from the calendar data
	-- , does keyword matching where appropriate,
	-- interprets start and end offsets, filters out
	-- unwanted events
	-- ***********************************************************

	local function getEvents(eventlist, keyword, startdelta, enddelta, ignoreAllDayEvent, ignoreKeyword, exactKeyword)
		b.DEBUG(3,"local function: getEvents")
		
		-- Create a global array of events. Each row [i] contains:
		-- [i][1] -- starttime in utc
		-- [i][2] -- endtime in utc
		-- [i][3] -- title as uppercase string
		-- [i][4] -- optional parameter as mixed case string
		-- [i][5] -- if All Day event then date in dd Mon format else ""
		-- [i][6] -- unique event end id == concatination of title,endtime
		-- [i][7] -- unique event start id == concatination of title,startime

		b.setVar("GCal"..GC.device_idx.."NextEvent","Checking Events", 2)
		b.setVar("GCal"..GC.device_idx.."NextEventTime","." , 2)
		b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
		b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)

		local globalstartend = "[" .. startdelta .. "," .. enddelta .. "]"

		GC.Events = {} -- reset the Events
		local keywordarray = {}

		-- if one or more keywords, parse them into a usable form
		if (keyword ~= "") then
			local i = 0
			for key in string.gmatch(keyword,"([^;]+)") do
				i = i + 1
				keywordarray[i] = {}
				local _,_,keywordstartend = string.find(key,"%[(.-)%]") -- does the keyword have a start / stop delta i.e. something in []?
				local _,_,keywordparameter = string.find(key,"%{(.-)%}") -- does the keyword have a parameter i.e. something in {}?
				if (keywordstartend ~= nil) then
					keywordarray[i][2] = "[" .. keywordstartend .. "]"
					key = string.gsub(key, "%[(.-)%]", "") -- remove anything in []
				else
					keywordarray[i][2] = ""
				end
				if (keywordparameter ~= nil) then
					keywordarray[i][3] = keywordparameter
					key = string.gsub(key, "%{(.-)%}", "") -- remove anything in {}
				else
					keywordarray[i][3] = ""
				end
				keywordarray[i][1] = trimString(upperCase(key))
			end
		else
			keywordarray[1] = {}
			keywordarray[1][1] = "" -- no keyword
			keywordarray[1][2] = ""
			keywordarray[1][3] = ""
		end

		-- iterate through each of the events and interpret any special instructions
		local numberEvents = #eventlist
		b.DEBUG(2,"There were " .. numberEvents .. " events retrieved")
		local j = 1
		local EventsToday = 0
		local EventsLeftToday = 0
		for i=1,numberEvents do
			
			-- get the start and end times
			local eventStart = (eventlist[i]['start'].date or eventlist[i]['start'].dateTime)
			local allDayEvent = allDay(eventStart) -- flag if all day event
			local starttime = strToTime(eventStart)
			local endtime = strToTime(eventlist[i]['end'].date or eventlist[i]['end'].dateTime)
			
			-- get the title and any start / stop delta or parameter
			local eventname = (eventlist[i]['summary'] or "No Name")
			eventname = trimString(eventname)
			local _,_,eventstartend = string.find(eventname,"%[(.-)%]") -- does the event have a start / stop delta
			local _,_,eventparameter = string.find(eventname,"%{(.-)%}") -- does the event have a parameter
			local eventtitle = string.gsub(eventname, "%{(.-)%}", "") -- remove anything in {}
			eventtitle = string.gsub(eventtitle, "%[(.-)%]", "") -- remove anything in []
			eventtitle= trimString(upperCase(eventtitle)) -- force to upper case and trim

			-- get the description and any start / stop delta or parameter
			local description = (eventlist[i]['description'] or "none")
			description = trimString(upperCase(description))
			local _,_,descriptionstartend = string.find(description,"%[(.-)%]") -- does the description have a start / stop delta
			local _,_,descriptionparameter = string.find(description,"%{(.-)%}") -- does the description have a parameter
			local descriptiontext = string.gsub(description, "%{(.-)%}", "") -- remove anything in {}
			descriptiontext = string.gsub(descriptiontext, "%[(.-)%]", "") -- remove anything in []
			descriptiontext = trimString(upperCase(descriptiontext))

			-- see if we have a keyword match in the title or the desciption
			local matchedEvent = false
			local matchAllEvents = false
			local matchedDescription = false
			local keyindex = 1
			local numkeywords = #keywordarray

			if (keyword == "") then -- all events match
					matchAllEvents = true
			else
				for j = 1,numkeywords do
				if (exactKeyword == "true") then -- we test for an exact match
					if ((eventtitle == keywordarray[j][1]) or (descriptiontext == keywordarray[j][1])) then
						matchedEvent = true
						keyindex = j
						break
					end
				else -- we test for a loose match
					matchedEvent = string.find(eventtitle,keywordarray[j][1])
					matchedDescription = string.find(descriptiontext,keywordarray[j][1])
					matchedEvent = matchedEvent or matchedDescription
					if matchedEvent then
						keyindex = j
						break
					end
				end
				end
		end

		-- add start/end delta if specified
		local effectiveEventName
		eventname = eventtitle

		if (matchedEvent and (keywordarray[keyindex][2] ~= "")) then -- offset specified for the keyword takes precedence
			eventname = eventname .. keywordarray[keyindex][2]
		elseif (eventstartend ~= nil) then
			eventname = eventname .. "[" .. eventstartend .. "]"
		elseif (descriptionstartend ~= nil) then
			eventname = eventname .. "[" .. descriptionstartend .. "]"
		else -- use the global value
			eventname = eventname .. globalstartend
		end

		-- add parameter if specified
		local value = ""
		if (matchedEvent and (keywordarray[keyindex][3] ~= "")) then -- parameter specified for the keyword takes precedence
			value = trimString(keywordarray[keyindex][3])
		elseif (eventparameter ~= nil) then
			value = trimString(eventparameter)
		elseif (descriptionparameter ~= nil) then
			value = trimString(descriptionparameter)
		end

		effectiveEventName = eventname .. "{" ..value .. "}" -- this normalizes the 'value' parameter
		b.DEBUG(3,"Effective Event Name " .. effectiveEventName)

		-- apply any start end offsets
		local _,_,startoffset,endoffset = string.find(eventname,"%[%s*([+-]?%d+)%s*,%s*([+-]?%d+)%s*%]") -- look in the title
		startoffset = tonumber(startoffset)
		endoffset = tonumber(endoffset)
		if (startoffset and endoffset) then
			starttime = starttime + (startoffset * 60)
			endtime = endtime + (endoffset * 60)
		end

		-- filter out unwanted events
		if ((ignoreAllDayEvent == "true") and (allDayEvent ~= "")) then -- it's an all day event and to be ignored
			b.DEBUG(2,"All Day Event " .. effectiveEventName .. " Ignored")
		elseif ((ignoreKeyword == "true") and matchedEvent) then -- matched keyword and to be ignored
			b.DEBUG(2,"Event matched keyword " .. effectiveEventName .. " Ignored")
		elseif ((endtime - starttime) < 60) then -- event must be at least 1 minute
			b.DEBUG(2,"Event less than 1 minute: " .. effectiveEventName .. " Ignored")
		elseif ((not matchAllEvents and matchedEvent) or matchAllEvents or (ignoreKeyword == "true") ) then -- good to go
			
			-- add a new entry into the list of valid events
			GC.Events[j] = {}
			GC.Events[j][1] = starttime
			GC.Events[j][2] = endtime
			GC.Events[j][3] = eventtitle
			GC.Events[j][4] = value
			if ((startoffset == 0) and (endoffset == 0)) then
				GC.Events[j][5] = allDayEvent
			else
				GC.Events[j][5] = ""
			end
			local ta = os.date("*t", endtime + GC.timeZone)
			local s1 = string.format("%02d/%02d %02d:%02d",ta.month, ta.day, ta.hour, ta.min)
			GC.Events[j][6] = eventtitle .. " " ..s1
			ta = os.date("*t", starttime + GC.timeZone)
			s1 = string.format("%02d/%02d %02d:%02d",ta.month, ta.day, ta.hour, ta.min)
			GC.Events[j][7] = eventtitle .. " " ..s1
			j = j + 1
			if (((starttime >= GC.startofDay) and (starttime <= GC.endofDay)) or ((endtime >= GC.startofDay) and (endtime <= GC.endofDay)))   then
				EventsToday = EventsToday + 1
			end
			if (((starttime > GC.utc + 1) and (starttime < GC.endofDay)) or ((endtime > GC.utc + 1) and ((endtime - 2) < GC.endofDay))) then -- minus 2 sec to catch all day event
				EventsLeftToday = EventsLeftToday + 1
			end
		end
		end
		-- sort the events by time
		table.sort(GC.Events, compare)
	 
		b.DEBUG(3, "Events Today = " .. tostring(EventsToday))
		b.DEBUG(3, "Events Left Today = " .. tostring(EventsLeftToday))
		b.DEBUG(3, "Next event time = " .. os.date("%c", GC.Events[1][1] + GC.timeZone))
		b.DEBUG(3, "Next event stop = " .. os.date("%c", GC.Events[1][2] + GC.timeZone))
		b.setVar("GCal"..GC.device_idx.."EventsToday",EventsToday, 0)
		b.setVar("GCal"..GC.device_idx.."EventsLeftToday",EventsLeftToday, 0)
		b.setVar("GCal"..GC.device_idx.."NextStart", GC.Events[1][1] + GC.timeZone, 0)
		b.setVar("GCal"..GC.device_idx.."NextStop", GC.Events[1][2] + GC.timeZone, 0)
	end

	-- ************************************************************
	-- This local function determines if there is an event to trigger on
	-- ************************************************************

	local function nextEvent()
		local eventtitle = "No more events today"
		local nextEventTime = "."
		local nextEvent = -1
		local index = 0
		local numberEvents = #GC.Events
		local format1 = '<span style="color: grey;">' -- future events are shown in grey
		local format2 = '</span>'

		GC.nextTimeCheck = GC.now + GC.Interval
		-- local currentStart , currentEnd = 0,0
		
		for i = 1,numberEvents do
			if ((GC.Events[i][1] <= GC.utc) and (GC.utc < GC.Events[i][2])) then -- we are inside an event
				format1 = ""
				format2 = ""
				nextEvent = i
				index = i
				eventtitle = GC.Events[i][3]
				GC.nextTimeCheck = GC.Events[i][2] + GC.timeZone -- in local time
				-- currentStart = GC.Events[i][1]
				-- currentEnd = GC.Events[i][2]
				break
			elseif ((nextEvent == -1) and (GC.Events[i][1] >= GC.utc)) then -- future event
				nextEvent = 0
				index = i
				eventtitle = GC.Events[i][3]
				GC.nextTimeCheck = GC.Events[i][1] + GC.timeZone -- in local time
				break -- only need the first one
			end
		end

		if (nextEvent ~= -1) then
			nextEventTime = os.date("%H:%M %b %d", GC.Events[index][1] + GC.timeZone) .. " to " .. os.date("%H:%M %b %d", GC.Events[index][2] + GC.timeZone)
		        b.setVar("GCal"..GC.device_idx.."NextStart", GC.Events[index][1] + GC.timeZone, 0)
                        b.setVar("GCal"..GC.device_idx.."NextStop", GC.Events[index][2] + GC.timeZone, 0)
		end

		if (eventtitle == "No more events today") then
			b.setVar("GCal"..GC.device_idx.."NextEvent", format1 .. string.sub(eventtitle,1,40) .. format2, 2)
			b.setVar("GCal"..GC.device_idx.."NextStart", 0, 0)
	                b.setVar("GCal"..GC.device_idx.."NextStop", 0, 0)
		else
			b.setVar("GCal"..GC.device_idx.."NextEvent", format1 .. string.sub(eventtitle,1,40) .. '<BR/><span style="font-weight: normal;">' .. nextEventTime .. "</span>" .. format2, 2)
		end
		b.setVar("GCal"..GC.device_idx.."NextEventTime", nextEventTime, 2)
		b.DEBUG(2,"Next Event: " .. eventtitle .. "<BR/>" .. nextEventTime)
		return nextEvent
	end

	function setTrippedOff(tripped)
		b.DEBUG(3,"local function: setTrippedOff")

		--b.setVar("GCal"..GC.device_idx.."Value", "", 2)
		GC.trippedEvent = ""
		b.setVar("GCal"..GC.device_idx.."TrippedEvent", GC.trippedEvent, 2)
		
		if (tonumber(tripped) == 1) then
			b.setVar("GCal"..GC.device_idx.."Tripped", 0, 0)
			b.DEBUG(1,"Event-End " .. GC.trippedID .. " Finished")
		else
			b.DEBUG(1,"Event-End " .. GC.trippedID .. " Inactive")
		end
		
		GC.trippedID = ""
		b.setVar("GCal"..GC.device_idx.."TrippedID", GC.trippedID, 2)
		b.setVar("GCal"..GC.device_idx.."displaystatus", 0, 0)
	end

	function setTripped(i, tripped)
		GC.trippedIndex = i
		if ((GC.Events[i][6] == GC.trippedID)) then -- in the same event
			if (tonumber(tripped) == 1) then
				b.DEBUG(1,"Event-Start " .. GC.Events[i][7] .. " is already Tripped")
			else
				b.DEBUG(1,"Event-Start " .. GC.Events[i][7] .. " is already Active")
			end
			return
		end
		
		local delay = 5 -- propogation delay for off / on transition
		
		if (tonumber(tripped) == 1 and (GC.Events[i][6] ~= GC.trippedID)) then -- logically a new event
			if ((GC.Events[i][7] == GC.trippedID) and (GC.retrip == "false")) then
				-- if the name and time for the start of the next event = the prior event finish and we should not retrip
				GC.trippedID = GC.Events[i][6] -- update with the continuation event
				b.setVar("GCal"..GC.device_idx.."TrippedID", GC.trippedID, 2)
				b.DEBUG(1,"Continuing prior event " .. GC.trippedID)
				return
			else -- finish the previous and start the new event
				tripped = setTrippedOff(i,1)
				b.DEBUG(2,"WE CAN'T WAIT, CAN WE? Waiting " .. delay .. " sec to trigger the next event")
				-- luup.call_timer("setTrippedOn",1,delay,"","") -- wait 'delay' sec for the off status to propogate
				setTrippedOn() -- WE CAN'T WAIT, CAN WE?
			end
			return
		end
		if (tonumber(tripped) == 0) then
			tripped = setTrippedOff(i,0) -- could have been a non-tripped but active event
			b.DEBUG(2,"WE CAN'T WAIT, CAN WE? Waiting " .. delay .. " sec to activate the next event")
			-- luup.call_timer("setTrippedOn",1,delay,"","") -- wait 'delay' sec for the off status to propogate
			setTrippedOn() -- WE CAN'T WAIT, CAN WE?
		end
	end

	function setTrippedOn()
		local i = GC.trippedIndex
		local nextEventTime = os.date("%H:%M %b %d", GC.Events[i][1] + GC.timeZone) .. " to " .. os.date("%H:%M %b %d", GC.Events[i][2] + GC.timeZone)
		b.setVar("GCal"..GC.device_idx.."NextEvent", GC.Events[i][3].. '<BR/><span style="font-weight: normal;">' .. nextEventTime .. "</span>", 2)
		b.setVar("GCal"..GC.device_idx.."Value", GC.Events[i][4], 2)
		GC.trippedEvent = GC.Events[i][3]
		b.setVar("GCal"..GC.device_idx.."TrippedEvent", GC.trippedEvent, 2)
		GC.trippedID = GC.Events[i][6] -- the end id for the event
		b.setVar("GCal"..GC.device_idx.."TrippedID", GC.trippedID, 2)
		
		if (GC.Keyword ~= "") or (GC.triggerNoKeyword == "true") then
			b.setVar("GCal"..GC.device_idx.."Tripped", 1, 0)
			b.setVar("GCal"..GC.device_idx.."displaystatus", 100, 0)
			b.DEBUG(1,"Event-Start " .. GC.Events[i][7] .. " Tripped")
		else
			b.setVar("GCal"..GC.device_idx.."displaystatus", 50, 0)
			b.DEBUG(1,"Event-Start " .. GC.Events[i][7] .. " Active")
		end
	end

	-- Safety pig has arrived!
	--
	--  _._ _..._ .-',     _.._(`))
	-- '-. `     '  /-._.-'    ',/
	--    )         \            '.
	--   / _    _    |             \
	--  |  a    a    /              |
	--  \   .-.                     ;  
	--   '-('' ).-'       ,'       ;
	--      '-;           |      .'
	--         \           \    /
	--         | 7  .__  _.-\   \
	--         | |  |  ``/  /`  /
	--        /,_|  |   /,_/   /
	--           /,_/      '`-'
	--
	
	local function setNextTimeCheck() -- returns the actual time for the next check in local time
		if ((GC.nextTimeCheck - GC.now) > GC.Interval) then -- min check interval is gc_Interval
			GC.nextTimeCheck = GC.now + GC.Interval
			b.DEBUG(3, "nextTimeCheck is default interval")
		end
		if (GC.nextTimeCheck == GC.now) then -- unlikely but could happen
			GC.nextTimeCheck = GC.now + 60 -- check again in 60 seconds
					b.DEBUG(3, "nextTimeCheck is 10 seconds")
		end
		if (GC.nextTimeCheck > (GC.endofDay + GC.timeZone)) then -- force a check at midnight each day
			GC.nextTimeCheck = GC.endofDay + GC.timeZone + 60 --  after midnight
			b.DEBUG(3, "nextTimeCheck is midnight")
		end
		return GC.nextTimeCheck
	end


	-- ********************************************************************
	-- This is the plugin execution sequence
	-- ********************************************************************

	local function checkGCal(json) -- this is the main sequence
		b.DEBUG(3, "local function:  checkGCal")
		--get the value of variables that may have changed during a reload
		GC.trippedID = b.getVar("GCal"..GC.device_idx.."TrippedID")
		GC.trippedEvent = b.getVar("GCal"..GC.device_idx.."TrippedEvent")
		GC.trippedStatus = b.getVar("GCal"..GC.device_idx.. "Tripped")
		GC.Interval = b.getVar("GCal"..GC.device_idx.."Interval")
		GC.Interval = tonumber(GC.Interval) * 60 -- convert to seconds since it's specified in minutes
		
		-- to avoid race conditions if there are multiple plugin instances
		-- we set set up a semaphore using a file
		if not getSemaphore() then
			return 5 -- could not get semaphore so try again later
		end  
	 
		-- get the start and stop window for requesting events from google
		local startmin, startmax = getStartMinMax(GC.StartDelta,GC.EndDelta)
		local events = nil 
		
		-- get the calendar information
		if GC.iCal then
			events = requestiCalendar(startmin, startmax)
		else
			events = requestCalendar(startmin, startmax, json)
		end
		
		local _ = releaseSemaphore("calendar check complete")

		-- update time since there may have been a semaphore or calendar related delay
		GC.now = os.time()
		GC.utc = GC.now - GC.timeZone

		if (events == nil) then -- error from calendar
			GC.access_error = GC.access_error + 1
			b.setVar("GCal"..GC.device_idx.."NextEvent", "Access or Calendar Error" , 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", tostring(GC.access_error), 2)
			GC.nextTimeCheck = GC.now + 500 -- check again in 500 seconds
			return setNextTimeCheck()
		end

		if (events == "No Events") then -- request succeeded but no events were found
			if (tonumber(GC.trippedStatus) == 1) then -- plugin was tripped and no events today
				local _ = setTrippedOff(GC.trippedStatus)
			end
			GC.nextTimeCheck = GC.now + GC.Interval
			return setNextTimeCheck()
		end

		-- get all the events in the current calendar window
		local _ = getEvents(events, GC.Keyword, GC.StartDelta, GC.EndDelta, GC.ignoreAllDayEvent, GC.ignoreKeyword, GC.exactKeyword)

		-- save a events, both calendar and active
		local _ = saveEvents(json)
			
		-- identify the active or next event
		local numActiveEvent = nextEvent()

		if (tonumber(numActiveEvent) < 1) then -- there were no active events so make sure any previous are off
			b.DEBUG(3,"Cancel any active event")
			GC.trippedStatus = setTrippedOff(GC.trippedStatus)
		else
			GC.trippedStatus = setTripped(numActiveEvent, GC.trippedStatus)
		end

		-- when to do the next check
		local nextTimeCheck = setNextTimeCheck()

		return nextTimeCheck
	end

	-- ********************************************************************
	-- Gets the Calendar ID and formats it for use in the API call and for display
	-- ********************************************************************
	function parseCalendarID(newID)
		b.setVar("GCal"..GC.device_idx.."CalendarID","", 2)
		GC.CalendarID = ""
		GC.iCal = false
		-- newID = string.gsub(newID,'%%','%%25') -- encode any %
		newID = string.gsub(newID,'%&','%%26') -- encode any &
		newID = string.gsub(newID,'#','%%23')  -- encode any #
		newID = string.gsub(newID,'+','%%2B')  -- encode any +
		newID = string.gsub(newID,'@','%%40')  -- encode any @
		if (string.find(newID,"ical") or string.find(newID,"iCal")) then -- treat as a public ical
		 GC.CalendarID = newID
		 GC.iCal = true
		else -- a regular google calendar   
		-- there are several forms of the calendar url so we try to make a good one 
		if string.find(newID,'(.-)src="http') then -- eliminate anything before src="http
			newID = string.gsub(newID,'(.-)src="http',"")
			newID = "http" .. newID
		end
		if string.find(newID,'calendar.google.com(.*)') then -- eliminate anything after calendar.google.com
			newID = string.gsub(newID,'calendar.google.com(.*)',"")
			newID = newID .. "calendar.google.com"
		end
		if string.find(newID,'gmail.com(.*)') then -- eliminate anything after gmail.com
			newID = string.gsub(newID,'gmail.com(.*)',"")
			newID = newID .. "gmail.com"
		end
		GC.CalendarID = string.gsub(newID,'(.*)%?src=',"") -- ?src=
		GC.CalendarID = string.gsub(GC.CalendarID,'(.*)%%26src=',"") -- &src=
		-- newID = url_decode(newID)
		end

		b.setVar("GCal"..GC.device_idx.."CalendarID", newID, 2)
		b.DEBUG(3,"Calendar ID is: " .. GC.CalendarID)
	end

	-- ********************************************************************
	-- This is the main program loop - it repeats by calling itself
	-- (non-recursive) using the luup.call_timer at interval determined
	-- from either event start / finish times or a maximum interval
	-- set by gc_Interval
	-- ********************************************************************

	function GCalMain(command)
			-- update time 
		GC.now = os.time()
		GC.utc = GC.now - GC.timeZone

		if (command == "fromAddEvent") then
			GC.allowCalendarUpdate = true
			b.DEBUG(2, "Calendar updates reinstated")
		end
		if (not GC.allowCalendarUpdate) then -- otherwise block updates when we are adding calendar events
			b.DEBUG(2, "Calendar updates blocked by Event Insert")
			return
		end
			
		-- Check to make sure there is a Calendar ID else stop the plugin
		if (GC.CalendarID == "") then
			b.setVar("GCal"..GC.device_idx.."NextEvent", "The CalendarID is not set", 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
			b.DEBUG(1, "The Calendar ID is not set")
			return
		else
			b.setVar("GCal"..GC.device_idx.."NextEvent", "The CalendarID is set", 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
		end
		
		-- if the plugin is not armed - stop 
		local Armed = b.getVar("GCal"..GC.device_idx.."Armed")
		if (Armed == 0) then
			local _ = setTrippedOff(1)
			b.setVar("GCal"..GC.device_idx.."NextEvent", "In Bypass Mode", 2)
			b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
			return
		end 

		local json = require("json")
		
		-- Check the calendar for any updates
		local nextCheckTime = checkGCal(json) -- returns time for next check in local time
		 
		-- update time: semaphores and http requests can take some time
		GC.now = os.time()
		GC.utc = GC.now - GC.timeZone
		
		--package.loaded.https = nil
		package.loaded.json = nil

		local lastCheck, nextCheck
		local delay = nextCheckTime - GC.now
		if (delay < 0) then
			delay = 60
			nextCheckTime = GC.now +60
			b.DEBUG(3,"Reset check time because delay was negative")
		end
		lastCheck = os.date("%Y-%m-%d at %H:%M:%S", GC.now)
		b.setVar("GCal"..GC.device_idx.."lastCheck", lastCheck, 2)
		nextCheck = os.date("%Y-%m-%d at %H:%M:%S", nextCheckTime)
		GC.nextCheckutc = strLocaltostrUTC(os.date("%Y-%m-%dT%H:%M:%S", nextCheckTime)) 
		b.setVar("GCal"..GC.device_idx.."nextCheck", nextCheck , 2)
		b.setVar("GCal"..GC.device_idx.."nextRun", nextCheckTime, 0)
		b.DEBUG(1,"Next check will be in " .. delay .. " sec on " .. nextCheck)

		GC.allowEventAdd = true -- allow events to be added to calendar
		if GC.retrip ~= GC.retripTemp then GC.retrip = GC.retripTemp end -- reset GC.retrip after calendar event update
	end

	-- ****************************************************************
	-- startup and related local functions are all here
	-- ****************************************************************

	local function getTimezone()
		local now = os.time()
		local date = os.date("!*t", now)
		date.isdst = os.date("*t").isdst
		local tz = (now - os.time(date))
		local tzhr = math.floor(tz/3600) -- whole hour
		local tzmin = math.floor(tz%3600/60 + 0.5) -- nearest integer 
		if (tzhr < 0) then
			tzmin = -tzmin
		end
		b.DEBUG(3, "Timezone is " ..tzhr .. " hrs and " .. tzmin .. " min")
		return tz, tzhr, tzmin
	end

	local function setupVariables()
		local isNewVarsCreated = false

		local function initUserVars(uservariablename, uservariablevalue, uservariabletype, ifnotvalue)
			local v = b.getVar(uservariablename)
			if (v == nil) then
				-- User variables are created here if they don't exist
				isNewVarsCreated = true
				b.setVar(uservariablename, uservariablevalue, uservariabletype)
				return uservariablevalue
			else
			-- First an integrity check if a "ifnotvalue" is supplied
				if (ifnotvalue ~= nil and v ~= ifnotvalue and v ~= uservariablevalue) then
					b.setVar(uservariablename, uservariablevalue, uservariabletype)
					return uservariablevalue
				else
					return v
				end
			end
		end

		initUserVars("GCal"..GC.device_idx.."Armed", 1, 0)
		initUserVars("GCal"..GC.device_idx.."Tripped", 0, 0)
		initUserVars("GCal"..GC.device_idx.."TrippedEvent", "", 2)
		initUserVars("GCal"..GC.device_idx.."TrippedID", "", 2)
		initUserVars("GCal"..GC.device_idx.."NextEvent", "", 2, "", "")
		initUserVars("GCal"..GC.device_idx.."NextEventTime", "", 2, "", "")
		GC.Interval = initUserVars("GCal"..GC.device_idx.."Interval", 180, 0) -- defaults to 3 hrs
		if (GC.Interval < 1) then
			b.setVar("GCal"..GC.device_idx.."Interval", 180, 0)
			GC.Interval = 180
		end
		GC.StartDelta = initUserVars("GCal"..GC.device_idx.."StartDelta", 0, 0)
		GC.EndDelta = initUserVars("GCal"..GC.device_idx.."EndDelta", 0, 0)
		GC.Keyword = initUserVars("GCal"..GC.device_idx.."Keyword", "", 2)
		GC.exactKeyword = initUserVars("GCal"..GC.device_idx.."exactKeyword", "true", 2, "false")
		GC.ignoreKeyword = initUserVars("GCal"..GC.device_idx.."ignoreKeyword", "false", 2, "true")
		GC.triggerNoKeyword = initUserVars("GCal"..GC.device_idx.."triggerNoKeyword", "false", 2, "true")
		GC.ignoreAllDayEvent = initUserVars("GCal"..GC.device_idx.."ignoreAllDayEvent", "false", 2, "true")
		GC.retrip = initUserVars("GCal"..GC.device_idx.."retrip", "true", 2, "false")
		--GC.firstToday = initUserVars("GCal"..GC.device_idx.."firstToday", "true", 2, "false")
		GC.retripTemp = GC.retrip
		GC.CalendarID = initUserVars("GCal"..GC.device_idx.."CalendarID", "", 2)
		if (string.find(GC.CalendarID,"ical") or string.find(GC.CalendarID,"iCal")) then -- treat as a public ical
			GC.iCal = true
		else
			GC.CalendarID = string.gsub(GC.CalendarID,"(.-)?src=","")
		end
		--initUserVars("GCal"..GC.device_idx.."jsonEvents", "[]", 2, "[]")
		initUserVars("GCal"..GC.device_idx.."jsonActiveEvents", "[]", 2, "[]")
		initUserVars("GCal"..GC.device_idx.."ActiveEvents", "", 2)
		initUserVars("GCal"..GC.device_idx.."EventsToday", 0, 0)
		initUserVars("GCal"..GC.device_idx.."EventsLeftToday", 0, 0)
		initUserVars("GCal"..GC.device_idx.."lastCheck", os.date("%Y-%m-%dT%H:%M:%S", os.time()), 2)
		initUserVars("GCal"..GC.device_idx.."nextCheck", os.date("%Y-%m-%dT%H:%M:%S", os.time()) , 2)
		initUserVars("GCal"..GC.device_idx.."nextRun", os.time(), 0)
		b.debug = initUserVars("GCal"..GC.device_idx.."debug", 3, 0)
		n1 = initUserVars("GCal"..GC.device_idx.."displaystatus", 0, 0)
		if (n1 > 100) then b.setVar("GCal"..GC.device_idx.."displaystatus", 100, 0) end
		return not isNewVarsCreated
	end

	function GCalStartup()
		GC.device_idx = myGCalDevs.calendarDevices.idxs[iGCal]
		b.DEBUG(3,"Calendar device " .. myGCalDevs.calendarDevices.names[iGCal] .. " (idx:" .. GC.device_idx .. " )  initializing")
		b.debug = b.getVar("GCal"..GC.device_idx.."debug") or 3
		GC.jsonEventsfile = GC.pluginpath .. "events"..GC.device_idx..".json" -- Found calendar events in json format

		-- make sure we have a plugin specific directory
		local result = osExecute("/bin/ls " .. GC.pluginpath)

		if (result ~= 0 and result ~= true) then -- if the directory does not exist, it gets created
			result = osExecute("/bin/mkdir " .. GC.pluginpath)
			if (result ~= 0 and result ~= true) then
				b.DEBUG(1, "Fatal Error could not create plugin directory")
				return
			end
			osExecute("/bin/chmod 777 " .. GC.pluginpath) -- To do: chown to the same as it's parent
		end

		-- force a reset of the semaphore file
		osExecute("/bin/rm -f " .. GC.semfile)
		
		-- clean up any token files from previous version 
		result = osExecute("bin/rm -f " .. GC.pluginpath .. "*.token")
		
		-- clean up the old script file
		--result = osExecute("bin/rm -f " .. GC.jwt)
		 
		if not getSemaphore() then
			--luup.call_timer("GCalStartup", 1,10,"","delayedstart") -- could not get semaphore try later
			-- We don't need a loop here, dow we?
			--GCalStartup()
			b.DEBUG(3, "Could not get semaphore... should try again later")
			return 
		end

		-- Initialize all the plugin variables
		if not(setupVariables()) then
			b.DEBUG(1, "New user variables were created. Please run again.")
			b.setVar("GCal"..GC.device_idx.."NextEvent", "New user variables were created. Please run again.", 2)
			return
		else
			b.DEBUG(1, "Variables initialized ...")
		end

		-- check to see if we have json.lua module
		local result = osExecute("/bin/ls " .. GC.jsonlua)
		if (not result) then
			b.DEBUG(3, "Downloading json.lua ...")
			local url = "https://raw.githubusercontent.com/craigmj/json4lua/master/json/json.lua"
			local result = osExecute("curl " .. url .. "|sed 's/loadstring/load/g'|tr -d '\\r' > " .. GC.jsonlua) -- download and replace deprecated function loadstring with new function load
			result = osExecute("/bin/ls " .. GC.jsonlua)
			if (not result) then
				b.setVar("GCal"..GC.device_idx.."NextEvent", "Missing file: " .. GC.jsonlua, 2)
				b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
				b.DEBUG(3, "Fatal Error - Could not download file" .. GC.jsonlua)
				local _ = releaseSemaphore("Fatal Error getting json.lua")
				return
			end
		end

		 -- check to see if openssl is on the system
		--local stdout = io.popen("sudo dpkg -l | awk '/ openssl/ {print $3}'")
		--local version = stdout:read("*a")
		--version = version:match("([^%s]+)") or false
		--stdout:close()
		--b.DEBUG(3, "Existing openssl version is: " .. tostring(version))
		--if not version then
			--b.DEBUG(3,"Installing openssl")
			-- install the default version for the vera model
			--local result = osExecute ("/bin/opkg update && opkg install openssl-util")
			
			--if (result ~= 0) then
			--b.setVar("GCal"..GC.device_idx.."NextEvent", "Fatal error: openssl not found", 2)
			--b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
			--b.DEBUG(3, "Fatal Error - openssl not found")
			--local _ = releaseSemaphore("Fatal error getting openssl")
			--return
			--end
		--end

		--check for new credentials file
		local json = require("json")
		local credentials = checkforcredentials(json)
		package.loaded.json = nil
		if not credentials then
				b.setVar("GCal"..GC.device_idx.."NextEvent", "Fatal Error - Could not get credentials", 2)
				b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
				b.DEBUG(3, "Fatal Error - Could not get credentials" .. GC.pluginpath .. GC.credentialfile)
				local _ = releaseSemaphore("Fatal error getting credentials")
			return
		end
		 
		-- Get the Time Zone info
		GC.timeZone, GC.timeZonehr, GC.timeZonemin = getTimezone()

		-- Warp speed Mr. Sulu
		b.DEBUG(1, "Running Plugin ...")
		b.setVar("GCal"..GC.device_idx.."NextEvent", "Successfully Initialized", 2)
		b.setVar("GCal"..GC.device_idx.."NextEventTime", ".", 2)
		--luup.call_timer("GCalMain",1,1,"","")
		GCalMain() -- No waiting here
		local _ = releaseSemaphore("initialization complete")

		-- Add text (if it's available) to display in text device
		local result = commandArray["Variable:".."GCal"..GC.device_idx.."NextEvent"]
		if (result ~= nil) then
			commandArray["UpdateDevice"] = myGCalDevs.textDevices.idxs[iGCal].."|0|"..result
		end

		-- Switch the calendar switch (if calendar was tripped and switch needs to be set)
		if otherdevices[myGCalDevs.calendarDevices.names[iGCal]] ~= nil then b.DEBUG(3, "Switch recent status: " .. otherdevices[myGCalDevs.calendarDevices.names[iGCal]]) end

		if GC.trippedEvent == "" then result = "Off" else result = "On" end
		
		if (otherdevices[myGCalDevs.calendarDevices.names[iGCal]] ~= result) then
			b.DEBUG(3, "Setting new Switch status to: " .. result)
			commandArray[myGCalDevs.calendarDevices.names[iGCal]] = result
		end

	end
	
	GCalStartup()
	
end
	
return commandArray
