---@diagnostic disable
-- CTLD_utils.lua
-- Static utility module: geometry, vectors, DCS spawn helpers, table utilities.
-- Originally derived from MIST (https://github.com/mrSkortch/MissionScriptingTools).
-- CTLD no longer depends on MIST; all required functions are embedded here.
-- NOTE: Do NOT re-introduce a MIST dependency. If a utility is missing, port it from MIST into this file.


-- 1. Définition du namespace global 'ctld'
ctld = ctld or {}

-- ====================================================================================================
-- CLASS ctld.utils
-- ====================================================================================================

local utils = {}
ctld.utils = utils
if not ctld.utils.marks then ctld.utils.marks = {}; end

-- ====================================================================================================
-- Version comparison — "MAJOR.MINOR.PATCH" with an optional "-pre" suffix (e.g. "2.0.0-rc1").
-- Semver rules: a release outranks the same version's pre-release; pre-release trailing numbers
-- compare numerically (rc10 > rc2). Returns -1 (a<b), 0 (a==b), 1 (a>b).
-- ====================================================================================================
local function _parseVersion(v)
    v = tostring(v or "")
    local major, minor, patch, pre = v:match("^(%d+)%.(%d+)%.(%d+)%-?(.*)$")
    return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0,
           (pre ~= nil and pre ~= "" and pre or nil)
end

function ctld.utils.compareVersions(a, b)
    local a1, a2, a3, ap = _parseVersion(a)
    local b1, b2, b3, bp = _parseVersion(b)
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    if a3 ~= b3 then return a3 < b3 and -1 or 1 end
    -- Equal cores: compare pre-release. No pre = release = highest.
    if ap == bp then return 0 end
    if not ap then return 1 end
    if not bp then return -1 end
    local an = tonumber(ap:match("%d+"))
    local bn = tonumber(bp:match("%d+"))
    if an and bn and an ~= bn then return an < bn and -1 or 1 end
    if ap == bp then return 0 end
    return ap < bp and -1 or 1
end

function ctld.utils.drawQuad(coalitionId, vec3Points1To4, message)
    local coalitionId = coalitionId or 2
    local markId = ctld.utils.getNextMarkId()

    -- Color
    local tableColor = { 0, 0, 255, 0.4 }  --blue  by default
    if coalitionId == 1 then
        tableColor = { 1, 0, 0, 0.4 }      --red  % of (r,g,b,alpha)    red
    elseif coalitionId == 2 then
        tableColor = { 0, 0, 255, 0.4 }    --blue  % of (r,g,b,alpha)   blue
    elseif coalitionId == 0 then
        tableColor = { 2, 173, 33, 0.4 }   --green  % of (r,g,b,alpha)  neutral
    elseif coalitionId == -1 then
        tableColor = { 247, 179, 30, 0.4 } --orange  % of (r,g,b,alpha) All
    end

    local tableFillColor = { 0, 0, 255, 0.4 } --tableColor
    local lineType = 1                        --solid
    local message = message or ""
    ctld.utils.marks[markId] = message

    --trigger.action.quadToAll(number coalition , number id , vec3 point1 , vec3 point2 , vec3 point3 , vec3 point4 , table color , table fillColor , number lineType , boolean readOnly, string message)
    trigger.action.quadToAll(coalitionId, markId,
        vec3Points1To4[1], vec3Points1To4[2], vec3Points1To4[3], vec3Points1To4[4],
        tableColor, tableFillColor, lineType, true, message)

    --[[-example ------------------------------------------------------------
local heliName = "h1-1"
local triggerUnitObj = Unit.getByName(heliName)
local vec3StartPoint = triggerUnitObj:getPosition().p
local vec3EndPoint = {x = vec3StartPoint.x+1000,z=vec3StartPoint.z+1000,y=vec3StartPoint.y}
ctld.utils.drawQuad(coalitionId, vec3Points1To4, message)
]] --
    return markId
end

--------------------------------------------------------------------------------------------------------
-- Calculates the absolute coordinates (x, y, heading, altitude) of a target point
-- based on a reference point and a relative offset, respecting the DCS coordinate system
-- (X=North, Y=East) and magnetic declination.
---------------------------------------------------------------------------------------------
-- @param refX X coordinate (North) of the reference point.
-- @param refY Y coordinate (East) of the reference point.
-- @param refHeading True/Geographic Heading of the reference unit in degrees.
-- @param refAltitude Altitude of the reference unit.
-- @param offsetAngleInDegrees Angle of the offset relative to the reference heading (0 = directly ahead).
-- @param offsetDistance Distance of the offset.
-- @param offsetHeading True/Geographic Heading for the final point.
-- @param offsetAltitude Altitude difference to add to the reference altitude.
-- @param magneticDeclinationInDegrees Magnetic Declination (subtract from True Heading to get Magnetic Heading).
--
-- @return x Absolute X coordinate (North) of the target point.
-- @return y Absolute Y coordinate (East) of the target point.
-- @return magneticHeadingInDegrees Magnetic Heading of the target point in degrees.
-- @return altitude Absolute altitude of the target point.
---
function ctld.utils.getRelativeCoords(
    refX, refY, refHeading, refAltitude,
    offsetAngleInDegrees, offsetDistanceInMeters,
    offsetHeadingInDegrees, offsetAltitudeInMeters,
    magneticDeclinationInDegrees
)
    -------------------------------------------------------------------------
    -- 1. Convert reference heading (radians → degrees)
    --    refHeading is a DCS true heading in radians, clockwise, 0 = North.
    -------------------------------------------------------------------------
    local refHeadingDeg = math.deg(refHeading)

    -------------------------------------------------------------------------
    -- 2. Compute the world angle used to project the new position.
    --    offsetAngleInDegrees is relative to the aircraft's heading.
    -------------------------------------------------------------------------
    local worldAngleDeg = refHeadingDeg + offsetAngleInDegrees

    -- Convert to radians for math.sin/cos (DCS uses clockwise headings)
    local worldAngleRad = math.rad(worldAngleDeg)

    -------------------------------------------------------------------------
    -- 3. Compute position deltas using DCS Cartesian coordinates:
    --    X axis = South/North, positive to the North.
    --    Y axis (vec3.z) = West/East, positive to the East.
    -------------------------------------------------------------------------
    local dx = math.cos(worldAngleRad) * offsetDistanceInMeters
    local dy = math.sin(worldAngleRad) * offsetDistanceInMeters

    local newX = refX + dx
    local newY = refY + dy

    -------------------------------------------------------------------------
    -- 4. Compute the object's final magnetic heading.
    --
    --    refHeadingDeg            = reference TRUE heading
    --    + offsetHeadingInDegrees = rotation relative to the reference
    --    - magneticDeclination    = convert true → magnetic
    -------------------------------------------------------------------------
    local magneticHeadingDeg =
        refHeadingDeg +
        offsetHeadingInDegrees -
        magneticDeclinationInDegrees

    -- Normalize to 0–360°
    magneticHeadingDeg = (magneticHeadingDeg % 360 + 360) % 360

    -------------------------------------------------------------------------
    -- 5. Compute altitude
    -------------------------------------------------------------------------
    local newAltitude = refAltitude + offsetAltitudeInMeters

    return newX, newY, magneticHeadingDeg, newAltitude
end

--------------------------------------------------------------------------------------------------------
-- Return a Vec2 point relative to  a reference point (position & heading DCS)
function ctld.utils.GetRelativeVec2Coords(refVec2Point, refHeadingInRadians, distanceFromRef,
                                          angleInDegreesFromRefHeading)
    -- absolue Heading in radians
    local absoluteHeadingInRadians = refHeadingInRadians + math.rad(angleInDegreesFromRefHeading)
    -- in DCS : x = Nord (+), z = Est (+)
    local dx = math.cos(absoluteHeadingInRadians) * distanceFromRef -- displacement North/South
    local dy = math.sin(absoluteHeadingInRadians) * distanceFromRef -- displacement Est/West

    local newCoords = {
        x = refVec2Point.x + dx,
        y = refVec2Point.y + dy,
    }
    return newCoords
end

------------------------------------------------------------------------------------
--- Calculates the relative bearing of a destination point from a reference point.
--- The bearing is expressed relative to the reference heading.
---
--- Input conventions (DCS-compatible):
---  - refLat / destLat are in decimal degrees
---  - refLon / destLon are in decimal degrees
---  - refHeading is in DEGREES (user-facing), converted to radians internally
---  - bearing output can be in radians, degrees, or clock position
---
--- Output formats:
---  - "radian" : relative bearing in radians [-pi .. +pi]
---  - "degree" : relative bearing in degrees [0 .. 360[
---  - "clock"  : clock position (12 = ahead, 3 = right, 6 = behind, etc.)
---
--- @param caller string Calling context (for logging)
--- @param refLat number Reference latitude in decimal degrees
--- @param refLon number Reference longitude in decimal degrees
--- @param refHeadingInDegrees number Heading in degrees (0-360)
--- @param destLat number Destination latitude in decimal degrees
--- @param destLon number Destination longitude in decimal degrees
--- @param resultFormat string Output format ("radian", "degree", "clock")
--- @return number, string Relative bearing and format
------------------------------------------------------------------------------------
function ctld.utils.getRelativeBearing(
    caller,
    refLat,
    refLon,
    refHeadingInDegrees,
    destLat,
    destLon,
    resultFormat
)
    -- Input validation
    if not refLat or not refLon or not refHeadingInDegrees or not destLat or not destLon then
        if env and env.error then
            env.error("ctld.utils.getRelativeBearing()." .. tostring(caller) ..
                ": All input values (refLat, refLon, refHeadingInDegrees, destLat, destLon) must be provided.")
        end
        return 0, resultFormat
    end

    -- Convert degrees to radians for calculations
    local refLatRad = math.rad(refLat)
    local refLonRad = math.rad(refLon)
    local destLatRad = math.rad(destLat)
    local destLonRad = math.rad(destLon)

    -- Calculate delta in radians
    local dLat = destLatRad - refLatRad
    local dLon = destLonRad - refLonRad

    -- Calculate bearing using haversine-like formula (forward azimuth)
    -- atan2(sin(dLon) * cos(destLat), cos(refLat) * sin(destLat) - sin(refLat) * cos(destLat) * cos(dLon))
    local trueBearingRad = math.atan2(
        math.sin(dLon) * math.cos(destLatRad),
        math.cos(refLatRad) * math.sin(destLatRad) -
        math.sin(refLatRad) * math.cos(destLatRad) * math.cos(dLon)
    )

    -- Normalize true bearing to [0, 2π)
    if trueBearingRad < 0 then
        trueBearingRad = trueBearingRad + 2 * math.pi
    end

    -- Convert reference heading from degrees to radians
    local refHeadingRad = math.rad(refHeadingInDegrees)

    -- Compute relative bearing (subtract reference heading)
    local relativeRad = trueBearingRad - refHeadingRad

    -- Normalize relative bearing to [-π, +π]
    relativeRad = (relativeRad + math.pi) % (2 * math.pi) - math.pi

    -- Output formats
    if resultFormat == "radian" then
        return relativeRad, resultFormat
    end

    -- Convert to degrees [0, 360)
    local relativeDeg = math.deg(relativeRad)
    if relativeDeg < 0 then
        relativeDeg = relativeDeg + 360
    end

    if resultFormat == "clock" then
        -- 12 o'clock = ahead (0°), each hour = 30 degrees
        -- Clock 3 = right (90°), 6 = behind (180°), 9 = left (270°)
        local clock = math.floor((relativeDeg + 15) / 30) % 12
        if clock == 0 then clock = 12 end
        return clock, resultFormat
    end

    -- Default: degrees [0, 360)
    return relativeDeg, "degree"
end

--------------------------------------------------------------------------------------------------------
--- Returns magnetic variation of given DCS point (vec2 or vec3).
-- borrowed from mist
function ctld.utils.getNorthCorrectionInRadians(caller, vec2OrVec3Point) --gets the correction needed for true north (magnetic variation)
    if vec2OrVec3Point == nil then
        if env and env.error then
            env.error("ctld.utils.getNorthCorrectionInRadians()." .. tostring(caller) .. ": Invalid point provided.")
        end
        return 0
    end

    local point = ctld.utils.deepCopy("ctld.utils.getNorthCorrectionInRadians()", vec2OrVec3Point)
    if point == nil then
        return 0
    else
        if not point.z then --Vec2; convert to Vec3
            point.z = point.y
            point.y = 0
        end
        local lat, lon = coord.LOtoLL(point)
        local north_posit = coord.LLtoLO(lat + 1, lon)
        return math.atan(north_posit.z - point.z, north_posit.x - point.x)
    end
end

--------------------------------------------------------------------------------------------------------
--- @function ctld.utils:getHeadingInRadians
-- @-- borrowed from mist
---@param unitObject any
---@param rawHeading boolean (true=geographic/false=magnetic)
---@return integer       --- @--return "magneticHeading : "..tostring(math.deg(ctld.utils.getHeadingInRadians(triggerUnitObj, false)))..", geographicHeading : "..tostring(math.deg(ctld.utils.getHeadingInRadians(triggerUnitObj, true)))
function ctld.utils.getHeadingInRadians(caller, unitObject, rawHeading) --rawHeading: boolean (true=geographic/false=magnetic)
    if not unitObject then
        if env and env.error then
            env.error("ctld.utils.getHeadingInRadians()." .. tostring(caller) .. ": Invalid unit object provided.")
        end
        return 0
    end
    rawHeading = rawHeading or false
    local unitpos = unitObject:getPosition()
    if unitpos then
        local HeadingInRadians = math.atan2(unitpos.x.z, unitpos.x.x)
        if not rawHeading then
            HeadingInRadians = HeadingInRadians +
                ctld.utils.getNorthCorrectionInRadians("ctld.utils.getHeadingInRadians()", unitpos.p)
        end
        if HeadingInRadians < 0 then
            HeadingInRadians = HeadingInRadians + 2 * math.pi -- put heading in range of 0 to 2*pi
        end
        return HeadingInRadians
    end
    return 0
end

--------------------------------------------------------------------------------------------------------
--- Converts a Vec2 to a Vec3.
-- @-- borrowed from mist
-- @tparam Vec2 vec the 2D vector
-- @param y optional new y axis (altitude) value. If omitted it's 0.
function ctld.utils.makeVec3FromVec2OrVec3(caller, vec, y)
    if not vec then
        if env and env.error then
            env.error("ctld.utils.makeVec3FromVec2OrVec3()." .. tostring(caller) .. ": Invalid vector provided.")
        end
        return nil
    end
    if not vec.z then
        if vec.alt and not y then
            y = vec.alt
        elseif not y then
            y = 0
        end
        return { x = vec.x, y = y, z = vec.y }
    else
        return { x = vec.x, y = vec.y, z = vec.z } -- it was already Vec3, actually.
    end
end

--------------------------------------------------------------------------------------------------------
--- Converts a Vec3 to a Vec2.
-- @tparam Vec3 vec the 3D vector
-- @return vector converted to Vec2
function ctld.utils.makeVec2FromVec3OrVec2(caller, vec)
    if vec == nil then
        if env and env.error then
            env.error("ctld.utils.makeVec2FromVec3OrVec2()." .. tostring(caller) .. ": Invalid vector provided.")
        end
        return nil
    end
    if vec.z then
        return { x = vec.x, y = vec.z }
    else
        return { x = vec.x, y = vec.y } -- it was actually already vec2.
    end
end

--------------------------------------------------------------------------------------------------------
--- Build a position string for a DCS unit (lat/lon + MGRS + altitude).
-- Returns "" if JTAC_location config is false or unit is nil.
-- @param unit DCS Unit object
-- @return string  e.g. " @ 42°15.3'N 041°42.1'E - MGRS 38TML… - ALTI: 250 m / 820 ft"
function ctld.utils.getPositionString(unit)
    if ctld.gs("JTAC_location") == false or unit == nil then
        return ""
    end
    local _lat, _lon  = coord.LOtoLL(unit:getPosition().p)
    local _latLngStr  = ctld.utils.tostringLL("getPositionString", _lat, _lon, 3,
        ctld.gs("location_DMS"))
    local _mgrsString = ctld.utils.tostringMGRS("getPositionString",
        coord.LLtoMGRS(coord.LOtoLL(unit:getPosition().p)), 5)
    local _alt        = land.getHeight(ctld.utils.makeVec2FromVec3OrVec2("getPositionString",
        unit:getPoint()))
    return " @ " .. _latLngStr ..
        " - MGRS " .. _mgrsString ..
        " - ALTI: " .. ctld.utils.round("getPositionString", _alt, 0) ..
        " m / " .. ctld.utils.round("getPositionString", _alt / 0.3048, 0) .. " ft"
end

--------------------------------------------------------------------------------------------------------
--- @function ctld.utils:rotateVec3
-- Calcule l'offset cartésien absolu en appliquant la rotation du cap de l'appareil.
-- (Designed for the data format: relative = {x, y, z})
function ctld.utils.rotateVec3(relativeVec, headingDeg)
    local x_rel = relativeVec.x
    local z_rel = relativeVec.z
    -- y_rel n'est pas utilisé dans le calcul de rotation, mais sera dans le retour
    local y_rel = relativeVec.y or 0

    -- Input validation (X and Z are mandatory)
    if x_rel == nil or z_rel == nil then
        local msg = "CTLD.utils:rotateVec3: Missing X or Z component in relative position data."
        if env and env.error then
            env.error(msg)
            -- Raises an error to be caught by pcall (if called within one)
            error(msg)
        else
            error(msg)
        end
    end

    local headingRad = math.rad(headingDeg)
    local cos_h = math.cos(headingRad)
    local sin_h = math.sin(headingRad)

    local x_rot = (z_rel * sin_h) + (x_rel * cos_h)
    local z_rot = (z_rel * cos_h) - (x_rel * sin_h)

    return { x = x_rot, y = y_rel, z = z_rot }
end

--------------------------------------------------------------------------------------------------------
-- Add 2 position vectors (Vec3) of DCS.
function ctld.utils.addVec3(vec1, vec2)
    return {
        -- Use or 0 to avoid 'nil'
        x = (vec1.x or 0) + (vec2.x or 0),
        y = (vec1.y or 0) + (vec2.y or 0),
        z = (vec1.z or 0) + (vec2.z or 0),
    }
end

--------------------------------------------------------------------------------------------------------
--- Vector substraction.
-- @tparam Vec3 vec1 first vector
-- @tparam Vec3 vec2 second vector
-- @treturn Vec3 new vector, vec2 substracted from vec1.
function ctld.utils.subVec3(caller, vec1, vec2)
    if vec1 == nil or vec2 == nil then
        if env and env.error then
            env.error("ctld.utils.subVec3()." .. tostring(caller) .. ": Both input values cannot be nil.")
        end
        return nil
    end
    return { x = vec1.x - vec2.x, y = vec1.y - vec2.y, z = vec1.z - vec2.z }
end

--------------------------------------------------------------------------------------------------------
--- Vector dot product.
-- @tparam Vec3 vec1 first vector
-- @tparam Vec3 vec2 second vector
-- @treturn number dot product of given vectors
function ctld.utils.multVec3(caller, vec1, vec2)
    if vec1 == nil or vec2 == nil then
        if env and env.error then
            env.error("ctld.utils.multVec3()." .. tostring(caller) .. ": Both input values cannot be nil.")
        end
        return 0
    end
    return vec1.x * vec2.x + vec1.y * vec2.y + vec1.z * vec2.z
end

--------------------------------------------------------------------------------------------------------
--- Returns the center of a zone as Vec3.
-- @-- borrowed from mist
-- @tparam string|table zone trigger zone name or table
-- @treturn Vec3 center of the zone
function ctld.utils.zoneToVec3(caller, zone, gl)
    if zone == nil then
        if env and env.error then
            env.error("ctld.utils.zoneToVec3()." .. tostring(caller) .. ": Invalid zone provided.")
        end
        return nil
    end

    ---@diagnostic disable: assign-type-mismatch
    local new = { x = 0, y = 0, z = 0 }
    if type(zone) == 'table' then
        if zone.point then
            new.x = zone.point.x
            new.y = zone.point.y
            new.z = zone.point.z
        elseif zone.x and zone.y and zone.z then
            local copied = ctld.utils.deepCopy("ctld.utils.zoneToVec3()", zone)
            if copied then
                new = copied
            end
        end
        return new
    elseif type(zone) == 'string' then
        zone = trigger.misc.getZone(zone)
        if zone then
            new.x = zone.point.x
            new.y = zone.point.y
            new.z = zone.point.z
        end
    end

    if new.x and gl then
        new.y = land.getHeight({ x = new.x, y = new.z })
    end
    return new
end

--------------------------------------------------------------------------------------------------------
--- Vector magnitude
-- @tparam Vec3 (3D with x,y,z)vec vector
-- @treturn number magnitude of vector vec
function ctld.utils.vec3Mag(caller, vec3)
    if vec3 == nil or vec3.x == nil or vec3.y == nil or vec3.z == nil then
        if env and env.error then
            env.error("ctld.utils.vec3Mag()." .. tostring(caller) .. ": Invalid vector provided.")
        end
        return 0
    end

    return (vec3.x ^ 2 + vec3.y ^ 2 + vec3.z ^ 2) ^ 0.5
end

--------------------------------------------------------------------------------------------------------
--- Returns distance in meters between two points.
-- @-- borrowed from mist
-- @tparam Vec2|Vec3 point1 first point
-- @tparam Vec2|Vec3 point2 second point
-- @treturn number distance between given points.
function ctld.utils.get2DDist(caller, point1, point2)
    if point1 == nil or point2 == nil then
        if env and env.error then
            env.error("ctld.utils.get2DDist()." .. tostring(caller) .. ": Both input values cannot be nil.")
        end
        return 0
    end
    if not point1 then
        ctld.logWarning("ctld.utils.get2DDist()  1st input value is nil")
    end
    if not point2 then
        ctld.logWarning("ctld.utils.get2DDist()  2nd input value is nil")
    end
    ---@type table
    point1 = ctld.utils.makeVec3FromVec2OrVec3("ctld.utils.get2DDist()", point1)
    ---@type table
    point2 = ctld.utils.makeVec3FromVec2OrVec3("ctld.utils.get2DDist()", point2)
    return ctld.utils.vec3Mag("ctld.utils.get2DDist()", { x = point1.x - point2.x, y = 0, z = point1.z - point2.z })
end

--get distance in meters assuming a Flat world
function ctld.utils.getDistance(caller, _point1, _point2)
    if _point1 == nil or _point2 == nil then
        if env and env.error then
            env.error("ctld.utils.getDistance()." .. tostring(caller) .. ": Both input values cannot be nil.")
        end
        return 0
    end
    local xUnit = _point1.x
    local yUnit = _point1.z
    local xZone = _point2.x
    local yZone = _point2.z

    local xDiff = xUnit - xZone
    local yDiff = yUnit - yZone

    return math.sqrt(xDiff * xDiff + yDiff * yDiff)
end

----------------------------------------------------------------------------------------------------------
-- gets the center of a bunch of points!
-- return proper DCS point with height
function ctld.utils.getCentroid(caller, _points)
    if _points == nil or #_points == 0 then
        if env and env.error then
            env.error("ctld.utils.getCentroid()." .. tostring(caller) .. ": Invalid points provided.")
        end
        return nil
    end
    local _tx, _ty = 0, 0
    for _index, _point in ipairs(_points) do
        _tx = _tx + _point.x
        _ty = _ty + _point.z
    end

    local _npoints = #_points

    local _point = { x = _tx / _npoints, z = _ty / _npoints }

    _point.y = land.getHeight({ x = _point.x, y = _point.z })

    return _point
end

--------------------------------------------------------------------------------------------------------
--- Simple rounding function.
-- @-- borrowed from mist
-- From http://lua-users.org/wiki/SimpleRound
-- use negative idp for rounding ahead of decimal place, positive for rounding after decimal place
-- @tparam number num number to round
-- @param idp
function ctld.utils.round(caller, num, idp)
    if num == nil or type(num) ~= "number" then
        if env and env.error then
            env.error("ctld.utils.round()." .. tostring(caller) .. ": Invalid number provided.")
        end
        return 0
    end
    local mult = 10 ^ (idp or 0)
    return math.floor(num * mult + 0.5) / mult
end

--------------------------------------------------------------------------------------------------------
-- initialize the random number generator to make it almost random
math.random(); math.random(); math.random()
--------------------------------------------------------------------------------------------------------
function ctld.utils.RandomReal(caller, mini, maxi)
    if mini == nil or maxi == nil then
        if env and env.error then
            env.error("ctld.RandomReal()." .. tostring(caller) .. ": Both min and max values must be provided.")
        end
        return 0
    end
    local rand = math.random()                 --random value between 0 and 1
    local result = mini + rand * (maxi - mini) --	scale the random value between [mini, maxi]
    return result
end

--------------------------------------------------------------------------------------------------------
--[[acc:
in DM: decimal point of minutes.
In DMS: decimal point of seconds.
position after the decimal of the least significant digit:
So:
42.32 - acc of 2.
]]
function ctld.utils.tostringLL(caller, lat, lon, acc, DMS)
    if lat == nil or lon == nil then
        if env and env.error then
            env.error("ctld.utils.tostringLL()." .. tostring(caller) .. ": Invalid latitude or longitude provided.")
        end
        return ""
    end
    local latHemi, lonHemi
    if lat > 0 then
        latHemi = 'N'
    else
        latHemi = 'S'
    end

    if lon > 0 then
        lonHemi = 'E'
    else
        lonHemi = 'W'
    end

    lat = math.abs(lat)
    lon = math.abs(lon)

    local latDeg = math.floor(lat)
    local latMin = (lat - latDeg) * 60

    local lonDeg = math.floor(lon)
    local lonMin = (lon - lonDeg) * 60

    if DMS then -- degrees, minutes, and seconds.
        local oldLatMin = latMin
        latMin = math.floor(latMin)
        local latSec = ctld.utils.round("ctld.utils.tostringLL()", (oldLatMin - latMin) * 60, acc)

        local oldLonMin = lonMin
        lonMin = math.floor(lonMin)
        local lonSec = ctld.utils.round("ctld.utils.tostringLL()", (oldLonMin - lonMin) * 60, acc)

        if latSec == 60 then
            latSec = 0
            latMin = latMin + 1
        end

        if lonSec == 60 then
            lonSec = 0
            lonMin = lonMin + 1
        end

        local secFrmtStr -- create the formatting string for the seconds place
        if acc <= 0 then -- no decimal place.
            secFrmtStr = '%02d'
        else
            local width = 3 + acc -- 01.310 - that's a width of 6, for example.
            secFrmtStr = '%0' .. width .. '.' .. acc .. 'f'
        end

        return string.format('%02d', latDeg) ..
            ' ' ..
            string.format('%02d', latMin) .. '\' ' .. string.format(secFrmtStr, latSec) .. '"' .. latHemi .. '	 '
            ..
            string.format('%02d', lonDeg) ..
            ' ' .. string.format('%02d', lonMin) .. '\' ' .. string.format(secFrmtStr, lonSec) .. '"' .. lonHemi
    else -- degrees, decimal minutes.
        latMin = ctld.utils.round("ctld.utils.tostringLL()", latMin, acc)
        lonMin = ctld.utils.round("ctld.utils.tostringLL()", lonMin, acc)

        if latMin == 60 then
            latMin = 0
            latDeg = latDeg + 1
        end

        if lonMin == 60 then
            lonMin = 0
            lonDeg = lonDeg + 1
        end

        local minFrmtStr -- create the formatting string for the minutes place
        if acc <= 0 then -- no decimal place.
            minFrmtStr = '%02d'
        else
            local width = 3 + acc -- 01.310 - that's a width of 6, for example.
            minFrmtStr = '%0' .. width .. '.' .. acc .. 'f'
        end

        return string.format('%02d', latDeg) .. ' ' .. string.format(minFrmtStr, latMin) .. '\'' .. latHemi .. '	 '
            .. string.format('%02d', lonDeg) .. ' ' .. string.format(minFrmtStr, lonMin) .. '\'' .. lonHemi
    end
end

--------------------------------------------------------------------------------------------------------
--- Returns MGRS coordinates as string.
-- @tparam string MGRS MGRS coordinates
-- @tparam number acc the accuracy of each easting/northing.
-- Can be: 0, 1, 2, 3, 4, or 5.
function ctld.utils.tostringMGRS(caller, MGRS, acc)
    if MGRS == nil or type(MGRS) ~= 'table' or not MGRS.UTMZone or not MGRS.MGRSDigraph then
        if env and env.error then
            env.error("ctld.utils.tostringMGRS()." .. tostring(caller) .. ": Invalid MGRS coordinates provided.")
        end
        return ""
    end
    if acc == 0 then
        return MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph
    else
        return MGRS.UTMZone ..
            ' ' ..
            MGRS.MGRSDigraph ..
            ' ' ..
            string.format('%0' .. acc .. 'd',
                ctld.utils.round("ctld.utils.tostringMGRS()", MGRS.Easting / (10 ^ (5 - acc)), 0))
            ..
            ' ' ..
            string.format('%0' .. acc .. 'd',
                ctld.utils.round("ctld.utils.tostringMGRS()", MGRS.Northing / (10 ^ (5 - acc)), 0))
    end
end

--------------------------------------------------------------------------------------------------------
ctld.utils.UniqIdCounter = 0 -- Static counter for unique IDs
--- @function ctld.utils:getNextUniqId
-- Generates an incremental unique ID, as required for 'unitId' in groupData.
function ctld.utils.getNextUniqId()
    ctld.utils.UniqIdCounter = ctld.utils.UniqIdCounter + 1
    return ctld.utils.UniqIdCounter
end

-- Mark ID counter — monotonically increasing, app-wide.
-- DCS: once removeMark(id) is called, that id is permanently invalid and must never be reused.
-- All Draw API callers (RECON, Beacon, drawQuad) share this counter to avoid collisions.
-- Encoded IDs use markId * 10 + offset (1–3 elements per logical mark).
-- Stored on ctld (persistent table via "ctld = ctld or {}") so it survives
-- ctld.utils table re-creation on each dcs-bridge re-injection.
-- Start at 10000 to stay far from any IDs burned by previous dcs-bridge re-injections.
if not ctld._markIdCounter then ctld._markIdCounter = 10000 end

--- Allocate the next unique mark ID for DCS Draw API calls.
-- Never reuse a previously allocated ID after removeMark() has been called on it.
-- @return number
function ctld.utils.getNextMarkId()
    ctld._markIdCounter = ctld._markIdCounter + 1
    return ctld._markIdCounter
end

--- Converts angle in radians to degrees.
-- @param angleInRadians angle in radians
-- @return angle in degrees
function ctld.utils.radianToDegree(caller, angleInRadians)
    if angleInRadians == nil or type(angleInRadians) ~= "number" then
        if env and env.error then
            env.error("ctld.utils.toDegree()." .. tostring(caller) .. ": Invalid angle provided.")
        end
        return 0
    end
    return math.deg(angleInRadians)
end

--------------------------------------------------------------------------------------------------------
--- @function ctld.utils:normalizeHeading
-- Normalise a heading between 0 et 360 degrees.
function ctld.utils.normalizeHeadingInDegrees(caller, offsetHeadingInDegrees)
    if offsetHeadingInDegrees == nil then
        if env and env.error then
            env.error("CTLD.utils.normalizeHeadingInDegrees()." .. tostring(caller) .. ": Invalid heading provided.")
        end
        return 0
    end
    local result = offsetHeadingInDegrees % 360
    if result < 0 then
        result = result + 360
    end
    return result
end

--------------------------------------------------------------------------------------------------------
--- @function ctld.utils:polarToCartesian
-- Converts a distance (rho), an angle (theta) and a reference heading (headingDeg)
-- into absolute Cartesian coordinates (x, z) on the DCS map.
-- @param distance number La distance au point de référence.
-- @param relativeAngle number L'angle relatif au point de référence (0 = devant, 90 = droite).
-- @param headingDeg number Le cap absolu de l'appareil (point de référence).
-- @return table L'offset cartésien absolu { x, y=0, z }.
function ctld.utils.polarToCartesian(distance, relativeAngle, headingDeg)
    local absoluteAngle = headingDeg + relativeAngle
    local angleRad = math.rad(absoluteAngle)

    -- Distance factor correction (20 m -> 10 m)
    local dist = (distance or 0) * 2

    -- X (Nord/Sud, l'axe de référence du cap 0°) : Utilise COS
    local x_rot = dist * math.cos(angleRad)

    -- Z (East/West): uses SIN. Standard trig sin(angle) increases CCW.
    -- Sign is kept as-is; DCS trigonometry convention may differ from standard.
    local z_rot = dist * math.sin(angleRad)

    return { x = x_rot, y = 0, z = z_rot }
end

--------------------------------------------------------------------------------------------------------
--- Converts kilometers per hour to meters per second.
-- @param kmph speed in km/h
-- @return speed in m/s
function ctld.utils.kmphToMps(caller, kmph)
    if kmph == nil or type(kmph) ~= "number" then
        if env and env.error then
            env.error("ctld.utils.kmphToMps()." .. tostring(caller) .. ": Invalid speed provided.")
        end
        return 0
    end
    return kmph / 3.6
end

--------------------------------------------------------------------------------------------------------
--- Builds a ground waypoint from a point definition.
-- No longer accepts path
function ctld.utils.buildWP(caller, point, overRideForm, overRideSpeed)
    if point == nil then
        if env and env.error then
            env.error("ctld.utils.buildWP()." .. tostring(caller) .. ": Invalid point provided.")
        end
        return nil
    end

    local wp = {}
    wp.x = point.x

    if point.z then
        wp.y = point.z
    else
        wp.y = point.y
    end
    local form, speed

    if point.speed and not overRideSpeed then
        wp.speed = point.speed
    elseif type(overRideSpeed) == 'number' then
        wp.speed = overRideSpeed
    else
        wp.speed = ctld.utils.kmphToMps("ctld.utils.buildWP()", 20)
    end

    if point.form and not overRideForm then
        form = point.form
    else
        form = overRideForm
    end

    if not form then
        wp.action = 'Cone'
    else
        form = string.lower(form)
        if form == 'off_road' or form == 'off road' then
            wp.action = 'Off Road'
        elseif form == 'on_road' or form == 'on road' then
            wp.action = 'On Road'
        elseif form == 'rank' or form == 'line_abrest' or form == 'line abrest' or form == 'lineabrest' then
            wp.action = 'Rank'
        elseif form == 'cone' then
            wp.action = 'Cone'
        elseif form == 'diamond' then
            wp.action = 'Diamond'
        elseif form == 'vee' then
            wp.action = 'Vee'
        elseif form == 'echelon_left' or form == 'echelon left' or form == 'echelonl' then
            wp.action = 'EchelonL'
        elseif form == 'echelon_right' or form == 'echelon right' or form == 'echelonr' then
            wp.action = 'EchelonR'
        else
            wp.action = 'Cone' -- if nothing matched
        end
    end

    wp.type = 'Turning Point'

    return wp
end

--------------------------------------------------------------------------------------------------------
function ctld.utils.getUnitsLOS(caller, unitset1, altoffset1, unitset2, altoffset2, radius)
    --ctld.logInfo("%s, %s, %s, %s, %s", unitset1, altoffset1, unitset2, altoffset2, radius)
    if unitset1 == nil or unitset2 == nil or altoffset1 == nil or altoffset2 == nil or radius == nil then
        if env and env.error then
            env.error("ctld.utils.getUnitsLOS()." .. tostring(caller) .. ": parameters sets cannot be nil.")
        end
        return {}
    end

    radius = radius or math.huge
    local unit_info1 = {}
    local unit_info2 = {}

    -- get the positions all in one step, saves execution time.
    for unitset1_ind = 1, #unitset1 do
        local unit1 = Unit.getByName(unitset1[unitset1_ind])
        if unit1 then
            local lCat = Object.getCategory(unit1)
            if ((lCat == 1 and unit1:isActive()) or lCat ~= 1) and unit1:isExist() == true then
                unit_info1[#unit_info1 + 1] = {}
                unit_info1[#unit_info1].unit = unit1
                unit_info1[#unit_info1].pos = unit1:getPosition().p
            end
        end
    end

    for unitset2_ind = 1, #unitset2 do
        local unit2 = Unit.getByName(unitset2[unitset2_ind])
        if unit2 then
            local lCat = Object.getCategory(unit2)
            if ((lCat == 1 and unit2:isActive()) or lCat ~= 1) and unit2:isExist() == true then
                unit_info2[#unit_info2 + 1] = {}
                unit_info2[#unit_info2].unit = unit2
                unit_info2[#unit_info2].pos = unit2:getPosition().p
            end
        end
    end

    local LOS_data = {}
    -- now compute los
    for unit1_ind = 1, #unit_info1 do
        local unit_added = false
        for unit2_ind = 1, #unit_info2 do
            if radius == math.huge or (ctld.utils.vec3Mag("ctld.utils.getUnitsLOS()", ctld.utils.subVec3("ctld.utils.getUnitsLOS()", unit_info1[unit1_ind].pos, unit_info2[unit2_ind].pos)) < radius) then -- inside radius
                local point1 = {
                    x = unit_info1[unit1_ind].pos.x,
                    y = unit_info1[unit1_ind].pos.y + altoffset1,
                    z =
                        unit_info1[unit1_ind].pos.z
                }
                local point2 = {
                    x = unit_info2[unit2_ind].pos.x,
                    y = unit_info2[unit2_ind].pos.y + altoffset2,
                    z =
                        unit_info2[unit2_ind].pos.z
                }
                if land.isVisible(point1, point2) then
                    if unit_added == false then
                        unit_added = true
                        LOS_data[#LOS_data + 1] = {}
                        LOS_data[#LOS_data].unit = unit_info1[unit1_ind].unit
                        LOS_data[#LOS_data].vis = {}
                        LOS_data[#LOS_data].vis[#LOS_data[#LOS_data].vis + 1] = unit_info2[unit2_ind].unit
                    else
                        LOS_data[#LOS_data].vis[#LOS_data[#LOS_data].vis + 1] = unit_info2[unit2_ind].unit
                    end
                end
            end
        end
    end

    return LOS_data
end

--------------------------------------------------------------------------------------------------------
--- Returns GroundUnitsListNames for a given coalition
function ctld.utils.getUnitsListNamesByCategory(caller, coalitionId, categoryTable)
    if coalitionId == nil then
        if env and env.error then
            env.error("ctld.utils.getUnitsListNamesByCategory()." ..
                tostring(caller) .. ": Invalid coalition ID provided.")
        end
        return {}
    end

    if categoryTable == nil then -- all categories requested
        categoryTable = {
            Group.Category.AIRPLANE,
            Group.Category.HELICOPTER,
            Group.Category.GROUND,
            Group.Category.SHIP,
            Group.Category.TRAIN,
        }
    end

    local groupList = {}
    for _, v in ipairs(categoryTable) do
        local categGroupList = coalition.getGroups(coalitionId, v)
        if categGroupList then
            for _, group in ipairs(categGroupList) do
                table.insert(groupList, group)
            end
        end
    end

    local UnitsListNames = {}
    for _, v in ipairs(groupList) do
        local groupUnits = v:getUnits()
        for _, vv in ipairs(groupUnits) do
            UnitsListNames[#UnitsListNames + 1] = vv:getName()
        end
    end
    return UnitsListNames
end

--------------------------------------------------------------------------------------------------------
-- same as getGroupPoints but returns speed and formation type along with vec2 of point}
function ctld.utils.getGroupRoute(caller, groupName, task)
    if groupName == nil then
        if env and env.error then
            env.error("ctld.utils.getGroupRoute()." .. tostring(caller) .. ": Invalid group name provided.")
        end
        return nil
    end
    -- refactor to search by groupId and allow groupId and groupName as inputs
    local gpId = groupName
    --if mist.DBs.MEgroupsByName[groupName] then
    if Group.getByName(groupName) then
        gpId = Group.getByName(groupName):getID()
    else
        ctld.logError("ctld.utils.getGroupRoute()." .. tostring(caller) .. "'%s' not found in mist.DBs.MEgroupsByName",
            groupName)
    end

    for coa_name, coa_data in pairs(env.mission.coalition) do
        if type(coa_data) == 'table' then
            if coa_data.country then --there is a country table
                for cntry_id, cntry_data in pairs(coa_data.country) do
                    for obj_cat_name, obj_cat_data in pairs(cntry_data) do
                        if obj_cat_name == "helicopter" or obj_cat_name == "ship" or obj_cat_name == "plane" or obj_cat_name == "vehicle" then                       -- only these types have points
                            if ((type(obj_cat_data) == 'table') and obj_cat_data.group and (type(obj_cat_data.group) == 'table') and (#obj_cat_data.group > 0)) then --there's a group!
                                for group_num, group_data in pairs(obj_cat_data.group) do
                                    if group_data and group_data.groupId == gpId then                                                                                -- this is the group we are looking for
                                        if group_data.route and group_data.route.points and #group_data.route.points > 0 then
                                            local points = {}

                                            for point_num, point in pairs(group_data.route.points) do
                                                local routeData = {}
                                                if env.mission.version > 7 and env.mission.version < 19 then
                                                    routeData.name = env.getValueDictByKey(point.name)
                                                else
                                                    routeData.name = point.name
                                                end
                                                if not point.point then
                                                    routeData.x = point.x
                                                    routeData.y = point.y
                                                else
                                                    routeData.point = point
                                                        .point --it's possible that the ME could move to the point = Vec2 notation.
                                                end
                                                routeData.form = point.action
                                                routeData.speed = point.speed
                                                routeData.alt = point.alt
                                                routeData.alt_type = point.alt_type
                                                routeData.airdromeId = point.airdromeId
                                                routeData.helipadId = point.helipadId
                                                routeData.type = point.type
                                                routeData.action = point.action
                                                if task then
                                                    routeData.task = point.task
                                                end
                                                points[point_num] = routeData
                                            end

                                            return points
                                        end
                                        ctld.logError('Group route not defined in mission editor for groupId: %s', gpId)
                                        return
                                    end --if group_data and group_data.name and group_data.name == 'groupname'
                                end     --for group_num, group_data in pairs(obj_cat_data.group) do
                            end         --if ((type(obj_cat_data) == 'table') and obj_cat_data.group and (type(obj_cat_data.group) == 'table') and (#obj_cat_data.group > 0)) then
                        end             --if obj_cat_name == "helicopter" or obj_cat_name == "ship" or obj_cat_name == "plane" or obj_cat_name == "vehicle" or obj_cat_name == "static" then
                    end                 --for obj_cat_name, obj_cat_data in pairs(cntry_data) do
                end                     --for cntry_id, cntry_data in pairs(coa_data.country) do
            end                         --if coa_data.country then --there is a country table
        end                             --if coa_name == 'red' or coa_name == 'blue' and type(coa_data) == 'table' then
    end                                 --for coa_name, coa_data in pairs(mission.coalition) do
end

--------------------------------------------------------------------------------------------------------
--- Returns the groupId for a given unit.
function ctld.utils.getGroupId(caller, _unitId)
    if _unitId == nil then
        if env and env.error then
            env.error("ctld.utils.getGroupId()." .. tostring(caller) .. ": Invalid unit provided.")
        end
        return nil
    end

    return _unitId:getGroup():getID()
end

--------------------------------------------------------------------------------------------------------
--- Spawns a static object to the game world.
-- Borrowed from mist.dynAddStatic and modified.
-- @todo write good docs
-- @tparam table staticObj table containing data needed for the object creation
function ctld.utils.dynAddStatic(caller, n)
    if n == nil then
        if env and env.error then
            env.error("ctld.utils.dynAddStatic()." .. tostring(caller) .. ": Invalid static object data provided.")
        end
        return false
    end
    --local newObj = mist.utils.deepCopy(n)
    local newObj = ctld.utils.deepCopy("ctld.utils.dynAddStatic()", n)
    if not newObj then return false end
    ---@type table
    newObj = newObj
    --ctld.logWarning(newObj)
    if newObj.units and newObj.units[1] then -- if its mist format
        for entry, val in pairs(newObj.units[1]) do
            if newObj[entry] and newObj[entry] ~= val or not newObj[entry] then
                newObj[entry] = val
            end
        end
    end
    --ctld.logInfo(newObj)

    local cntry = newObj.country
    if newObj.countryId then
        cntry = newObj.countryId
    end

    local newCountry = ''

    for countryId, countryName in pairs(country.name) do
        if type(cntry) == 'string' then
            cntry = cntry:gsub("%s+", "_")
            if tostring(countryName) == string.upper(cntry) then
                newCountry = countryName
            end
        elseif type(cntry) == 'number' then
            if countryId == cntry then
                newCountry = countryName
            end
        end
    end

    if newCountry == '' then
        ctld.logError("Country not found: %s", cntry)
        return false
    end

    if newObj.clone or not newObj.groupId then
        newObj.groupId = ctld.utils.getNextUniqId()
    end

    if newObj.clone or not newObj.unitId then
        newObj.unitId = ctld.utils.getNextUniqId()
    end

    newObj.name = newObj.name or newObj.unitName

    if newObj.clone or not newObj.name then
        newObj.name = (newCountry .. ' static ' .. tostring(newObj.groupId))
    end

    if not newObj.dead then
        newObj.dead = false
    end

    if not newObj.heading then
        newObj.heading = math.rad(math.random(360))
    end

    if newObj.categoryStatic then
        newObj.category = newObj.categoryStatic
    end
    if newObj.mass then
        newObj.category = 'Cargos'
    end

    if newObj.shapeName then
        newObj.shape_name = newObj.shapeName
    end

    if not newObj.shape_name then
        ctld.logInfo('shape_name not present')
    end
    if newObj.x and newObj.y and newObj.type and type(newObj.x) == 'number' and type(newObj.y) == 'number' and type(newObj.type) == 'string' then
        --ctld.logWarning(newObj)
        ctld.utils.spawnAs("STATIC", country.id[newCountry], newObj)

        return newObj
    end
    ctld.logError("Failed to add static object due to missing or incorrect value. X: %s, Y: %s, Type: %s", newObj.x,
        newObj.y, newObj.type)
    return false
end

--------------------------------------------------------------------------------------------------------
--- DCS category constants (informational — authoritative values validated against DCS API).
--
-- Group.Category  (second arg of coalition.addGroup):
--   AIRPLANE   = 0
--   HELICOPTER = 1
--   GROUND     = 2
--   SHIP       = 3
--   TRAIN      = 4
--
-- Object.Category (returned by object:getCategory()):
--   VOID    = 0
--   UNIT    = 1   — groups spawned via coalition.addGroup
--   WEAPON  = 2
--   STATIC  = 3   — objects spawned via coalition.addStaticObject
--   BASE    = 4
--   SCENERY = 5
--   CARGO   = 6
--
--- Unified DCS object spawner — SINGLE call-site for coalition.addGroup /
-- coalition.addStaticObject. All CTLD code must route through ctld.utils.spawnAs;
-- direct calls to the DCS APIs are forbidden outside this function.
--
-- @param spawnAs   string|number
--   String keys  : "GROUND" | "AIRPLANE" | "HELICOPTER" | "SHIP" | "TRAIN" | "STATIC"
--   Integer      : Group.Category value directly (0–4) — used by CTLDObjectRegistry
-- @param countryId number   country.id.* value
-- @param unitDef   table    DCS group or static descriptor
-- @return boolean, any      pcall result: (true, obj/group) or (false, errMsg)
local _SPAWN_CATEGORY_MAP = {
    AIRPLANE   = Group.Category.AIRPLANE,    -- 0
    HELICOPTER = Group.Category.HELICOPTER,  -- 1
    GROUND     = Group.Category.GROUND,      -- 2
    SHIP       = Group.Category.SHIP,        -- 3
    TRAIN      = Group.Category.TRAIN,       -- 4
}
function ctld.utils.spawnAs(spawnAs, countryId, unitDef)
    if spawnAs == "STATIC" then
        return pcall(coalition.addStaticObject, countryId, unitDef)
    elseif type(spawnAs) == "number" then
        return pcall(coalition.addGroup, countryId, spawnAs, unitDef)
    else
        local cat = _SPAWN_CATEGORY_MAP[spawnAs] or Group.Category.GROUND
        return pcall(coalition.addGroup, countryId, cat, unitDef)
    end
end

--- Descriptor-based variant: reads spawnAs from descriptor.spawnAs (default "GROUND").
-- @param descriptor table|nil  CTLD crate/vehicle descriptor
-- @param countryId  number
-- @param unitDef    table
-- @return boolean, any
function ctld.utils.spawnFromDescriptor(descriptor, countryId, unitDef)
    return ctld.utils.spawnAs(
        (descriptor and descriptor.spawnAs) or "GROUND",
        countryId, unitDef)
end

--------------------------------------------------------------------------------------------------------
--- Build a DCS group unitDef table ready for ctld.utils.spawnFromDescriptor.
-- Handles GROUND and non-ground (AIRPLANE, HELICOPTER, SHIP, TRAIN) categories.
-- STATIC objects use a different DCS schema and are not handled here.
--
-- For non-ground units with descriptor.isJTAC = true, an orbit + EPLRS route is embedded
-- (required by DCS at spawn time; cannot be assigned post-spawn for loitering platforms).
-- The orbit altitude is read from ctld.gs("JTAC_droneAltitude") (default 4000 m).
--
-- @param desc   table   crate descriptor { unit, spawnAs, isJTAC, … }
-- @param pos    vec3    world spawn position {x, y, z}
-- @param gname  string  DCS group name (pre-allocated by caller)
-- @param gid    number  DCS group id   (pre-allocated; used in non-ground groupId + EPLRS)
-- @param uid    number  DCS unit id    (pre-allocated; used in non-ground unitId)
-- @return table  unitDef
function ctld.utils.buildGroupUnitDef(desc, pos, gname, gid, uid)
    local spawnAs = (desc and desc.spawnAs) or "GROUND"
    local isAir   = spawnAs ~= "GROUND" and spawnAs ~= "STATIC"

    if not isAir then
        -- GROUND: minimal DCS group definition
        return {
            name  = gname,
            task  = "Ground Nothing",
            units = { {
                type    = desc.unit,
                name    = gname,
                x       = pos.x,
                y       = pos.z,
                heading = 0,
            } },
        }
    else
        -- Non-ground (AIRPLANE / HELICOPTER / SHIP / TRAIN)
        local alt     = ctld.gs("JTAC_droneAltitude")
        -- Same setting as the orbit route, so a drone spawns at the speed it will fly at. It used
        -- to be 54 m/s here against the orbit's own value, so the drone changed speed a couple of
        -- seconds after spawning — the same mismatch the altitude had.
        local speed   = ctld.utils.kmphToMps("ctld.utils.buildGroupUnitDef()", ctld.gs("JTAC_droneSpeed"))
        local uname   = gname .. "_1"
        local unitDef = {
            ["name"]          = gname,
            ["groupId"]       = gid,
            ["communication"] = true,
            ["frequency"]     = 124,
            ["visible"]       = false,
            ["hidden"]        = false,
            ["start_time"]    = 0,
            ["task"]          = "Ground Nothing",
            ["x"]             = pos.x,
            ["y"]             = pos.z,
            ["units"]         = {
                [1] = {
                    ["type"]     = desc.unit,
                    ["name"]     = uname,
                    ["unitId"]   = uid,
                    ["x"]        = pos.x,
                    ["y"]        = pos.z,
                    ["heading"]  = 0,
                    ["alt"]      = alt,
                    ["alt_type"] = "RADIO",
                    ["speed"]    = speed,
                    ["skill"]    = "Excellent",
                },
            },
        }
        -- Orbit + EPLRS route: required at spawn time for loitering JTAC platforms
        if desc and desc.isJTAC then
            unitDef["route"] = {
                ["points"] = {
                    [1] = {
                        ["alt"]                = alt,
                        ["alt_type"]           = "RADIO",
                        ["action"]             = "Turning Point",
                        ["type"]               = "Turning Point",
                        ["speed"]              = speed,
                        ["ETA"]                = 0,
                        ["ETA_locked"]         = true,
                        ["speed_locked"]       = true,
                        ["formation_template"] = "",
                        ["properties"]         = { ["addopt"] = {} },
                        ["x"]                  = pos.x,
                        ["y"]                  = pos.z,
                        ["task"]               = {
                            ["id"]     = "ComboTask",
                            ["params"] = {
                                ["tasks"] = {
                                    [1] = {
                                        ["number"]  = 1,
                                        ["auto"]    = true,
                                        ["id"]      = "WrappedAction",
                                        ["enabled"] = true,
                                        ["params"]  = {
                                            ["action"] = {
                                                ["id"]     = "EPLRS",
                                                ["params"] = {
                                                    ["value"]   = true,
                                                    ["groupId"] = gid,
                                                },
                                            },
                                        },
                                    },
                                    [2] = {
                                        ["number"]  = 2,
                                        ["auto"]    = false,
                                        ["id"]      = "Orbit",
                                        ["enabled"] = true,
                                        ["params"]  = {
                                            ["altitude"] = alt,
                                            ["pattern"]  = "Circle",
                                            ["speed"]    = speed,
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            }
        end
        return unitDef
    end
end

--------------------------------------------------------------------------------------------------------
--- Spawns a dynamic group into the game world.
-- Borrowed from mist.dynAddStatic and modified.
-- Will generate groupId, groupName, unitId, and unitName if needed
-- @tparam table newGroup table containting values needed for spawning a group.
function ctld.utils.dynAdd(caller, ng)
    if ng == nil then
        if env and env.error then
            env.error("ctld.utils.dynAdd()." .. tostring(caller) .. ": Invalid group data provided.")
        end
        return false
    end
    local newGroup = ctld.utils.deepCopy(" ctld.utils.dynAdd()", ng)
    if not newGroup then return false end
    ---@type table
    newGroup = newGroup
    --ctld.logWarning(newGroup)
    --mist.debug.writeData(mist.utils.serialize,{'msg', newGroup}, 'newGroupOrig.lua')
    local cntry = newGroup.country
    if newGroup.countryId then
        cntry = newGroup.countryId
    end

    local groupType = newGroup.category
    local newCountry = ''
    -- validate data
    for countryId, countryName in pairs(country.name) do
        if type(cntry) == 'string' then
            cntry = cntry:gsub("%s+", "_")
            if tostring(countryName) == string.upper(cntry) then
                newCountry = countryName
            end
        elseif type(cntry) == 'number' then
            if countryId == cntry then
                newCountry = countryName
            end
        end
    end

    if newCountry == '' then
        ctld.logError("Country not found: %s", cntry)
        return false
    end

    local newCat = ''
    for catName, catId in pairs(Unit.Category) do
        if type(groupType) == 'string' then
            if tostring(catName) == string.upper(groupType) then
                newCat = catName
            end
        elseif type(groupType) == 'number' then
            if catId == groupType then
                newCat = catName
            end
        end

        if catName == 'GROUND_UNIT' and (string.upper(groupType) == 'VEHICLE' or string.upper(groupType) == 'GROUND') then
            newCat = 'GROUND_UNIT'
        elseif catName == 'AIRPLANE' and string.upper(groupType) == 'PLANE' then
            newCat = 'AIRPLANE'
        end
    end
    local typeName
    if newCat == 'GROUND_UNIT' then
        typeName = ' gnd '
    elseif newCat == 'AIRPLANE' then
        typeName = ' air '
    elseif newCat == 'HELICOPTER' then
        typeName = ' hel '
    elseif newCat == 'SHIP' then
        typeName = ' shp '
    elseif newCat == 'BUILDING' then
        typeName = ' bld '
    end
    if newGroup.clone or not newGroup.groupId then
        newGroup.groupId = ctld.utils.getNextUniqId()
    end
    if newGroup.groupName or newGroup.name then
        if newGroup.groupName then
            newGroup.name = newGroup.groupName
        elseif newGroup.name then
            newGroup.name = newGroup.name
        end
    else
        newGroup.name = tostring(newCountry) .. "_" .. tostring(typeName) .. "_" .. tostring(newGroup.groupId)
    end

    if not newGroup.hidden then
        newGroup.hidden = false
    end

    if not newGroup.visible then
        newGroup.visible = false
    end

    if (newGroup.start_time and type(newGroup.start_time) ~= 'number') or not newGroup.start_time then
        if newGroup.startTime then
            newGroup.start_time = ctld.utils.round("mist.dynAdd()", newGroup.start_time)
        else
            newGroup.start_time = 0
        end
    end


    for unitIndex, unitData in pairs(newGroup.units) do
        local originalName = newGroup.units[unitIndex].unitName or newGroup.units[unitIndex].name
        if newGroup.clone or not unitData.unitId then
            newGroup.units[unitIndex].unitId = ctld.utils.getNextUniqId()
        end
        if newGroup.units[unitIndex].unitName or newGroup.units[unitIndex].name then
            if newGroup.units[unitIndex].unitName then
                newGroup.units[unitIndex].name = newGroup.units[unitIndex].unitName
            elseif newGroup.units[unitIndex].name then
                newGroup.units[unitIndex].name = newGroup.units[unitIndex].name
            end
        end
        if not unitData.name then
            newGroup.units[unitIndex].name = tostring(newGroup.name) .. '_unit_' .. tostring(unitIndex)
        end

        if not unitData.skill then
            newGroup.units[unitIndex].skill = 'Random'
        end

        if newCat == 'AIRPLANE' or newCat == 'HELICOPTER' then
            if newGroup.units[unitIndex].alt_type and newGroup.units[unitIndex].alt_type ~= 'BARO' or not newGroup.units[unitIndex].alt_type then
                newGroup.units[unitIndex].alt_type = 'RADIO'
            end
            if not unitData.speed then
                if newCat == 'AIRPLANE' then
                    newGroup.units[unitIndex].speed = 150
                elseif newCat == 'HELICOPTER' then
                    newGroup.units[unitIndex].speed = 60
                end
            end
            -- if not unitData.payload then
            --     newGroup.units[unitIndex].payload = mist.getPayload(originalName)
            -- end
            if not unitData.alt then
                if newCat == 'AIRPLANE' then
                    newGroup.units[unitIndex].alt = 2000
                    newGroup.units[unitIndex].alt_type = 'RADIO'
                    newGroup.units[unitIndex].speed = 150
                elseif newCat == 'HELICOPTER' then
                    newGroup.units[unitIndex].alt = 500
                    newGroup.units[unitIndex].alt_type = 'RADIO'
                    newGroup.units[unitIndex].speed = 60
                end
            end
        elseif newCat == 'GROUND_UNIT' then
            if nil == unitData.playerCanDrive then
                unitData.playerCanDrive = true
            end
        end
    end
    if newGroup.route then
        if newGroup.route and not newGroup.route.points then
            if newGroup.route[1] then
                local copyRoute = ctld.utils.deepCopy("ctld.utils.dynAdd()", newGroup.route)
                newGroup.route = {}
                newGroup.route.points = copyRoute
            end
        end
    else -- if aircraft and no route assigned. make a quick and stupid route so AI doesnt RTB immediately
        --if newCat == 'AIRPLANE' or newCat == 'HELICOPTER' then
        newGroup.route = {}
        newGroup.route.points = {}
        newGroup.route.points[1] = {}
        --end
    end
    newGroup.country = newCountry

    -- update and verify any self tasks
    if newGroup.route and newGroup.route.points then
        --ctld.logWarning(newGroup.route.points)
        for i, pData in pairs(newGroup.route.points) do
            if pData.task and pData.task.params and pData.task.params.tasks and #pData.task.params.tasks > 0 then
                for tIndex, tData in pairs(pData.task.params.tasks) do
                    if tData.params and tData.params.action then
                        if tData.params.action.id == "EPLRS" then
                            tData.params.action.params.groupId = newGroup.groupId
                        elseif tData.params.action.id == "ActivateBeacon" or tData.params.action.id == "ActivateICLS" then
                            tData.params.action.params.unitId = newGroup.units[1].unitId
                        end
                    end
                end
            end
        end
    end
    --mist.debug.writeData(mist.utils.serialize,{'msg', newGroup}, newGroup.name ..'.lua')
    --ctld.logWarning(newGroup)
    -- sanitize table
    newGroup.groupName = nil
    newGroup.clone = nil
    newGroup.category = nil
    newGroup.country = nil

    newGroup.tasks = {}

    for unitIndex, unitData in pairs(newGroup.units) do
        newGroup.units[unitIndex].unitName = nil
    end

    ctld.utils.log("TRACE", "ctld.utils.dynAdd newGroup=%s", tostring(newGroup.name))
    ctld.utils.spawnAs(newCat, country.id[newCountry], newGroup)

    return newGroup
end

--------------------------------------------------------------------------------------------------------
--Gets the average position of a group of units (by name)
function ctld.utils.getAvgPos(caller, unitNames)
    if unitNames == nil or #unitNames == 0 then
        if env and env.error then
            env.error("ctld.utils.getAvgPos()." .. tostring(caller) .. ": Invalid unit names provided.")
        end
        return nil
    end

    local avgX, avgY, avgZ, totNum = 0, 0, 0, 0
    for i = 1, #unitNames do
        local unit
        if Unit.getByName(unitNames[i]) then
            unit = Unit.getByName(unitNames[i])
        elseif StaticObject.getByName(unitNames[i]) then
            unit = StaticObject.getByName(unitNames[i])
        end
        if unit and unit:isExist() == true then
            local pos = unit:getPosition().p
            if pos then -- you never know O.o
                avgX = avgX + pos.x
                avgY = avgY + pos.y
                avgZ = avgZ + pos.z
                totNum = totNum + 1
            end
        end
    end
    if totNum ~= 0 then
        return { x = avgX / totNum, y = avgY / totNum, z = avgZ / totNum }
    end
end

--------------------------------------------------------------------------------------------------------
--- Checks if a value exists in an ipairs table.
function ctld.utils.isValueInIpairTable(caller, tab, value)
    if tab == nil or type(tab) ~= "table" then
        if env and env.error then
            env.error("ctld.utils.isValueInIpairTable()." .. tostring(caller) .. ": Invalid table provided.")
        end
        return false
    end
    for i, v in ipairs(tab) do
        if v == value then
            return true -- La valeur existe
        end
    end
    return false -- La valeur n'existe pas
end

--------------------------------------------------------------------------------------------------------
--- Counts the number of entries in a table.
function ctld.utils.countTableEntries(caller, _table)
    if type(_table) ~= "table" then
        if env and env.error then
            env.error("ctld.utils.countTableEntries()." .. tostring(caller) .. ": Invalid table provided.")
        end
        return 0
    end
    if _table == nil then
        return 0
    end

    local _count = 0
    for _key, _value in pairs(_table) do
        _count = _count + 1
    end

    return _count
end

--------------------------------------------------------------------------------------------------------
--- Creates a deep copy of a object.
-- @-- borrowed from mist
-- Usually this object is a table.
-- See also: from http://lua-users.org/wiki/CopyTable
-- @param object object to copy
-- @return copy of object
function ctld.utils.deepCopy(caller, object)
    local lookup_table = {}
    if object == nil then
        if env and env.error then
            env.error("ctld.utils.deepCopy()." .. tostring(caller) .. ": Attempt to deep copy a nil object.")
        end
        return nil
    end
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end

--------------------------------------------------------------------------------------------------------
--- return table as a lua script string
function ctld.utils.tableShowScript(caller, tblObj, tblName)
    if tblObj == nil then
        if env and env.error then
            env.error("ctld.utils.tableShowScript(): Attempt to show a nil table.")
        end
        return "nil"
    end
    if tblName == nil then
        tblName = "tbl"
    end

    local tScript = "local " .. tblName .. " = " .. ctld.utils.tableShow("ctld.utils.tableShowScript()", tblObj)
    return tScript
end

--------------------------------------------------------------------------------------------------------
--- Returns table in a easy readable string representation.
-- borrowed from mist
-- this function is not meant for serialization because it uses
-- newlines for better readability.
-- @param tbl table to show
-- @param loc
-- @param indent
-- @param tableshow_tbls
-- @return human readable string representation of given table
function ctld.utils.tableShow(caller, tbl, loc, indent, tableshow_tbls) --based on serialize_slmod, this is a _G serialization
    if tbl == nil then
        if env and env.error then
            env.error("ctld.utils.tableShow()." .. tostring(caller) .. ": Attempt to show a nil table.")
        end
        return "nil"
    end

    tableshow_tbls = tableshow_tbls or {} --create table of tables
    loc = loc or ""
    indent = indent or ""
    if type(tbl) == 'table' then --function only works for tables!
        tableshow_tbls[tbl] = loc
        local tbl_str = {}
        --tbl_str[#tbl_str + 1] = indent .. '{\n'
        tbl_str[#tbl_str + 1] = '{\n'

        for ind, val in pairs(tbl) do
            if type(ind) == "number" then
                tbl_str[#tbl_str + 1] = indent
                tbl_str[#tbl_str + 1] = loc .. '['
                tbl_str[#tbl_str + 1] = tostring(ind)
                tbl_str[#tbl_str + 1] = '] = '
            else
                tbl_str[#tbl_str + 1] = indent
                tbl_str[#tbl_str + 1] = loc .. '['
                tbl_str[#tbl_str + 1] = ctld.utils.basicSerialize("ctld.utils.tableShow()", ind)
                tbl_str[#tbl_str + 1] = '] = '
            end

            if ((type(val) == 'number') or (type(val) == 'boolean')) then
                tbl_str[#tbl_str + 1] = tostring(val)
                tbl_str[#tbl_str + 1] = ',\n'
            elseif type(val) == 'string' then
                tbl_str[#tbl_str + 1] = ctld.utils.basicSerialize("ctld.utils.tableShow()", val)
                tbl_str[#tbl_str + 1] = ',\n'
            elseif type(val) == 'nil' then -- won't ever happen, right?
                tbl_str[#tbl_str + 1] = 'nil,\n'
            elseif type(val) == 'table' then
                if tableshow_tbls[val] then
                    tbl_str[#tbl_str + 1] = tostring(val) .. ' already defined: ' .. tableshow_tbls[val] .. ',\n'
                else
                    --tableshow_tbls[val] = loc .. '[' .. ctld.utils.basicSerialize("ctld.utils.tableShow()", ind) .. ']'
                    --tbl_str[#tbl_str + 1] = tostring(val) .. ' '
                    --[[
                    tbl_str[#tbl_str + 1] = ctld.utils.tableShow(val,
                    loc .. '[' .. ctld.utils.basicSerialize("ctld.utils.tableShow()", ind) .. ']',
                    indent .. '    ',
                    tableshow_tbls) ]] --
                    tbl_str[#tbl_str + 1] = ctld.utils.tableShow("ctld.utils.tableShow()", val, loc, indent .. '    ')
                    tbl_str[#tbl_str + 1] = ',\n'
                end
            elseif type(val) == 'function' then
                if debug and debug.getinfo then
                    local fcnname = tostring(val)
                    local info = debug.getinfo(val, "S")
                    if info.what == "C" then
                        tbl_str[#tbl_str + 1] = string.format('%q', fcnname .. ', C function') .. ',\n'
                    else
                        if (string.sub(info.source, 1, 2) == [[./]]) then
                            tbl_str[#tbl_str + 1] = string.format('%q',
                                fcnname ..
                                ', defined in (' ..
                                info.linedefined .. '-' .. info.lastlinedefined .. ')' .. info.source) .. ',\n'
                        else
                            tbl_str[#tbl_str + 1] = string.format('%q',
                                    fcnname ..
                                    ', defined in (' .. info.linedefined .. '-' .. info.lastlinedefined .. ')') ..
                                ',\n'
                        end
                    end
                else
                    tbl_str[#tbl_str + 1] = 'a function,\n'
                end
            else
                tbl_str[#tbl_str + 1] = 'unable to serialize value type ' ..
                    ctld.utils.basicSerialize("ctld.utils.tableShow()", type(val)) .. ' at index ' .. tostring(ind)
            end
        end
        --string.sub("Hello, World!", -6, -1)
        if string.sub(table.concat(tbl_str), - #indent - 2, -1) == '{\n' then
            trigger.action.outText(string.sub(table.concat(tbl_str), - #indent - 2, -1), 10)
            for i = 1, #indent do
                tbl_str[#tbl_str] = nil
            end
            tbl_str[#tbl_str + 1] = '{}'
        else
            tbl_str[#tbl_str + 1] = indent .. '}'
        end
        return table.concat(tbl_str)
    end
end

--======================================================================================================
--- Serializes the give variable to a string.
-- borrowed from slmod
-- @param var variable to serialize
-- @treturn string variable serialized to string
function ctld.utils.basicSerialize(caller, var)
    if var == nil then
        if env and env.error then
            env.error("ctld.utils.basicSerialize()." .. tostring(caller) .. ": Attempt to serialize a nil variable.")
        end
        return "nil"
    else
        if ((type(var) == 'number') or
                (type(var) == 'boolean') or
                (type(var) == 'function') or
                (type(var) == 'table') or
                (type(var) == 'userdata')) then
            return tostring(var)
        elseif type(var) == 'string' then
            var = string.format('%q', var)
            return var
        end
    end
end

-- ====================================================================================================
-- SECTION: Shared file logger (EVO-12)
-- Shared across all CTLD modules. ctld.utils.initLog() must be called once during CTLD init.
-- On sanitized DCS (io unavailable) the pcall guard silently falls back to env.info only.
-- Keep ctld.debug=false on standard sanitized DCS installations.
-- ====================================================================================================

-- File handle stored in ctld namespace so it survives CTLD.lua re-injections.
-- (A local upvalue would be reset to nil on every re-injection of the merged script.)
-- ctld.__logFile is set by initLog(), cleared by closeLog(), never reset at module level.

-- Opens CTLD.log for writing if ctld.debug==true. Safe on sanitized DCS.
-- Always closes any existing handle before opening (allows test harness to reuse the file).
function ctld.utils.initLog()
    if ctld.gs("debug") ~= true then return end
    -- Close any previously open handle (prevents file lock accumulation across test reloads)
    if ctld.__logFile ~= nil then
        pcall(function()
            ctld.__logFile:flush(); ctld.__logFile:close()
        end)
        ctld.__logFile = nil
    end
    local path     = ctld.gs("ctldLogPath")
    local filePath = path .. "CTLD.log"
    local ok, _    = pcall(function()
        local f, err = io.open(filePath, "w")
        if f then
            ctld.__logFile = f
            ctld.__logFile:write(string.format("[CTLD] Log started : %s\n", os.date("%Y-%m-%d %H:%M:%S")))
            ctld.__logFile:flush()
        else
            env.info(string.format("[CTLD][WARN] Cannot open log file '%s': %s", filePath, tostring(err)))
        end
    end)
    if not ok then
        env.info("[CTLD][WARN] File logging unavailable (sanitized DCS). Set ctld.debug=false to suppress.")
    end
end

-- Logs a formatted message to env.info and to CTLD.log when debug file is open.
-- @param level  string  "INFO", "WARN", "ERROR", "TRACE"
-- @param fmt    string  format string (string.format style)
-- @param ...           format arguments
function ctld.utils.log(level, fmt, ...)
    local ok, msg = pcall(string.format, "[CTLD][" .. level .. "] " .. fmt, ...)
    if not ok then msg = "[CTLD][" .. level .. "] (log format error)" end
    env.info(msg)
    if not ctld.__logFile then
        pcall(ctld.utils.reopenLogAppend)
    end
    if ctld.__logFile then
        pcall(function()
            ctld.__logFile:write(msg .. "\n")
            ctld.__logFile:flush()
        end)
    end
    -- Guarded like CTLD_i18n.lua's _activeLang(), and for the same reason: log() runs during the
    -- main chunk, before ctld.initialize(). The scene files self-register at load time and log as
    -- they do, so this read happens against a config that is legitimately not loaded yet —
    -- CTLDConfig:getSetting refuses that by design (FIX-CONFIG-NOT-LOADED-GUARD), and an error
    -- raised from the logger aborts the whole file. Logging is infrastructure: it is called *from*
    -- initialization, so it cannot require initialization to have finished. env.info above is
    -- deliberately outside the guard — a pre-init line must still reach dcs.log.
    -- The inner read needs no guard of its own: reaching it proves the config is loaded.
    local okScreenLog, screenLog = pcall(ctld.gs, "debugScreenLog")
    if okScreenLog and screenLog == true then
        local duration = ctld.gs("debugScreenLogDuration")
        trigger.action.outText(msg, duration)
    end
end

-- Reopens CTLD.log in append mode (used after closeLog + read to resume logging).
-- File is opened only when config debug=true (ctld.gs("debug")).
function ctld.utils.reopenLogAppend()
    if ctld.__logFile ~= nil then return end -- already open
    if ctld.gs("debug") ~= true then return end
    local path     = ctld.gs("ctldLogPath")
    local filePath = path .. "CTLD.log"
    pcall(function()
        local f = io.open(filePath, "a")
        if f then ctld.__logFile = f end
    end)
end

-- Flushes and closes CTLD.log.
function ctld.utils.closeLog()
    if ctld.__logFile then
        pcall(function()
            ctld.__logFile:flush()
            ctld.__logFile:close()
        end)
        ctld.__logFile = nil
    end
end

-- ====================================================================================================
-- SECTION: Spawn positions on a random axis (used by CTLDCrateManager and CTLDSceneManager)
-- Local bbox containment helper (mirrors CTLDCrateManager._pointInBBox).
-- Returns true if world point pt lies inside the bbox of a unit described by unitPos + bbox.
local function _pointInBBoxLocal(unitPos, bbox, pt, margin)
    margin = margin or 0
    local dx = pt.x - unitPos.p.x
    local dy = pt.y - unitPos.p.y
    local dz = pt.z - unitPos.p.z
    local lx = dx * unitPos.x.x + dy * unitPos.x.y + dz * unitPos.x.z
    local ly = dx * unitPos.y.x + dy * unitPos.y.y + dz * unitPos.y.z
    local lz = dx * unitPos.z.x + dy * unitPos.z.y + dz * unitPos.z.z
    return lx >= (bbox.min.x - margin) and lx <= (bbox.max.x + margin)
       and ly >= (bbox.min.y - margin) and ly <= (bbox.max.y + margin)
       and lz >= (bbox.min.z - margin) and lz <= (bbox.max.z + margin)
end
-- Computes N absolute world positions along a single random axis (full 360° relative to unit heading).
-- Used for:
--   - CTLDCrateManager: pack and virtual unload (crate wave dispersion)
--   - CTLDSceneManager: step.axis positioning (random-axis object placement within a scene)
--
-- @param unit         DCS Unit object (requesting aircraft / scene trigger unit)
-- @param n              Number of positions to compute
-- @param safeDistance   Distance to first position in meters (varies by aircraft size)
-- @param spacing        Inter-position spacing in meters (default: ctld.gs("crateSpacing"))
-- @param axisOffsetDeg  Fixed axis angle in degrees relative to unit heading (nil = random 0-360).
--                       0 = straight ahead (12 o'clock), 180 = straight behind (6 o'clock).
--                       Pass a fixed value to align multiple crates in a predictable line.
-- @return table { positions = {{x,z}, ...}, clock = "1".."12", distance = safeDistance }
--
-- Clock convention: 0° ahead = 12 o'clock, 90° right = 3 o'clock, 180° behind = 6 o'clock.
-- ====================================================================================================

-- @param avoidBBoxes  array|nil  list of { unitPos, bbox } tables (DynamicCargo transports to avoid).
--                                 Each entry must have the same structure as CTLDCrateManager._checkNativeDCSCargo
--                                 transports: { unitPos = unit:getPosition(), bbox = desc.box }.
--                                 When provided, the chosen axis is rotated by 45° increments (up to 8 tries)
--                                 until all candidate positions are outside every listed bbox.
--                                 Falls back to the original axis if no free slot is found after 8 tries.
function ctld.utils.getSpawnObjectPositions(unit, n, safeDistance, spacing, axisOffsetDeg, avoidBBoxes)
    n             = n or 1
    spacing       = spacing or (ctld.gs and ctld.gs("crateSpacing")) or 5

    local unitPos = unit:getPoint()
    local unitHdg = ctld.utils.getHeadingInRadians("getSpawnObjectPositions", unit, true)

    -- Use provided axis or pick a random one (single axis for the whole wave)
    if axisOffsetDeg == nil then
        axisOffsetDeg = ctld.utils.RandomReal("getSpawnObjectPositions", 0, 360)
    end

    -- Helper: compute candidate positions for a given axis angle.
    local function _candidates(axisDeg)
        local pts = {}
        for i = 1, n do
            local dist = safeDistance + (i - 1) * spacing
            local pt   = ctld.utils.GetRelativeVec2Coords(
                { x = unitPos.x, y = unitPos.z },
                unitHdg,
                dist,
                axisDeg
            )
            pts[i] = { x = pt.x, z = pt.y }
        end
        return pts
    end

    -- Helper: returns true if any candidate point falls inside any avoided bbox.
    -- Uses a 2-D ground-plane check (y=0) so we don't need a full unit:getPosition() here —
    -- the avoidBBoxes entries already carry unitPos from _checkNativeDCSCargo.
    local function _anyCollision(pts)
        if not avoidBBoxes or #avoidBBoxes == 0 then return false end
        for _, avoid in ipairs(avoidBBoxes) do
            for _, pt in ipairs(pts) do
                local pt3 = { x = pt.x, y = avoid.unitPos.p.y, z = pt.z }
                if _pointInBBoxLocal(avoid.unitPos, avoid.bbox, pt3, 0.5) then
                    return true
                end
            end
        end
        return false
    end

    local chosenAxis = axisOffsetDeg
    local positions  = _candidates(chosenAxis)

    if avoidBBoxes and #avoidBBoxes > 0 then
        -- Rotate by 45° increments until all positions are clear (max 8 attempts = full circle).
        for attempt = 1, 7 do
            if not _anyCollision(positions) then break end
            chosenAxis = (chosenAxis + 45) % 360
            positions  = _candidates(chosenAxis)
        end
        -- If still colliding after 8 tries, keep last computed positions (best effort).
    end

    -- Clock bearing: axisOffsetDeg (0=12h, 30=1h, ..., 330=11h)
    local clockNum = math.floor(chosenAxis / 30 + 0.5) % 12
    if clockNum == 0 then clockNum = 12 end

    return {
        positions = positions,
        clock     = tostring(clockNum),
        distance  = safeDistance,
    }
end

-- ====================================================================================================
-- SECTION: Unit geometry helper
-- ====================================================================================================

-- Returns the safe spawn distance from a unit's centre (half bounding-box length along X axis).
-- Used to prevent spawned objects from colliding with the requesting aircraft.
-- @param unitName  string  DCS unit name
-- @return number (metres) or nil if unit not found / no bounding box
function ctld.utils.getSecureDistanceFromUnit(unitName)
    local unit = Unit.getByName(unitName)
    if not unit then return nil end
    local ok, box = pcall(function() return unit:getDesc().box end)
    if not ok or not box then return nil end
    -- Use the 2-D horizontal diagonal of the bounding box so the spawn point
    -- is guaranteed to lie outside the bbox regardless of spawn direction.
    -- Previous code used only the X half-extent and missed the lateral (Z) extent,
    -- causing crates to spawn inside large fixed-wing aircraft (e.g. C-130) bbox.
    local dx = math.max(math.abs(box.max.x), math.abs(box.min.x))
    local dz = math.max(math.abs(box.max.z), math.abs(box.min.z))
    return math.sqrt(dx * dx + dz * dz)
end

--- Returns true if a unit is airborne.
-- Primary check: unit:inAir() (DCS native).
-- Secondary check: if inAir()=true but the unit is below groundAglThreshold (config)
-- AND nearly stationary (speed < 0.5 m/s), it is treated as on the ground.
-- This handles high-chassis aircraft (e.g. CH-47) whose fuselage centre sits above
-- DCS's internal inAir threshold even when fully at rest on the ground.
-- @param unit DCS Unit
--- Safely return the DCS group ID for a unit.
-- Returns -1 if the unit is nil or has no group (avoids nil-chain crash on getGroup():getID()).
-- @param unit DCSUnit|nil
-- @return number  group ID, or -1 if unavailable
function ctld.utils.getGroupId(unit)
    if not unit then return -1 end
    local grp = unit:getGroup()
    return grp and grp:getID() or -1
end

-- @return boolean
function ctld.utils.inAir(unit)
    if not unit or not unit.inAir then return false end
    if not unit:inAir() then return false end

    -- inAir()=true: validate with AGL + velocity to reject high-chassis aircraft at rest.
    local aglThreshold = ctld.gs("groundAglThreshold")
    local pos = unit:getPoint()
    local agl = pos.y - land.getHeight({ x = pos.x, y = pos.z })
    if agl < aglThreshold then
        local vel    = unit:getVelocity()
        local speed2 = vel.x * vel.x + vel.y * vel.y + vel.z * vel.z
        if speed2 < 0.25 then return false end   -- stationary + low AGL → on the ground
    end

    return true
end

--- Calculate the ground landing position for a single parachuting object.
-- Accounts for forward inertia (shared direction from transport velocity)
-- plus per-unit lateral random drift.
-- Must be called once per unit at drop time (not deferred).
--
-- @param transport   DCS Unit  transport unit at the moment of drop
-- @param descentRate number    m/s descent rate (positive)
-- @return landPos vec3, descentTime number
--   landPos.y is the MSL ground height at the computed XZ position.
--   descentTime is in seconds.
function ctld.utils.calcDropPosition(transport, descentRate)
    local dropPos     = transport:getPoint()
    local velocity    = transport:getVelocity()
    local groundUnder = land.getHeight({ x = dropPos.x, y = dropPos.z })
    local dropAltAGL  = dropPos.y - groundUnder
    if dropAltAGL < 0 then dropAltAGL = 0 end
    local descentTime   = (descentRate and descentRate > 0) and (dropAltAGL / descentRate) or 0

    local inertiaFactor = ctld.gs and ctld.gs("parachuteInertiaFactor")
    local driftMin      = ctld.gs and ctld.gs("parachuteLateralDriftMin")
    local driftMax      = ctld.gs and ctld.gs("parachuteLateralDriftMax")

    local inertiaX      = (velocity.x or 0) * inertiaFactor * descentTime
    local inertiaZ      = (velocity.z or 0) * inertiaFactor * descentTime

    -- Wind drift: sample wind at drop altitude, propagate for full descent duration.
    -- atmosphere.getWind returns a velocity Vec3 {x,y,z} in m/s (direction the air moves toward).
    local wind  = atmosphere.getWind({ x = dropPos.x, y = dropPos.y, z = dropPos.z })
    local windX = (wind.x or 0) * descentTime
    local windZ = (wind.z or 0) * descentTime

    -- Random lateral scatter for gameplay dispersion (isotropic, independent per unit).
    local angle         = math.random(0, 359) * math.pi / 180
    local magnitude     = driftMin + math.random() * (driftMax - driftMin)

    local spawnX        = dropPos.x + inertiaX + windX + math.cos(angle) * magnitude
    local spawnZ        = dropPos.z + inertiaZ + windZ + math.sin(angle) * magnitude
    local spawnY        = land.getHeight({ x = spawnX, y = spawnZ })

    return { x = spawnX, y = spawnY, z = spawnZ }, descentTime
end

-- =====================================================================
-- Convenience log shorthands — route through ctld.utils.log.
-- These are used throughout src/ modules (CTLD_menu.lua etc.).
-- =====================================================================

---@param fmt string
---@param ... any
function ctld.logInfo(fmt, ...)
    ctld.utils.log("INFO", fmt, ...)
end

---@param fmt string
---@param ... any
function ctld.logWarning(fmt, ...)
    ctld.utils.log("WARNING", fmt, ...)
end

---@param fmt string
---@param ... any
function ctld.logError(fmt, ...)
    ctld.utils.log("ERROR", fmt, ...)
end

--- Send a text message to a coalition and optionally speak it via STTS.
---@param message     string   Long message (displayed on screen)
---@param displayFor  number   Display duration in seconds
---@param side        number   coalition.side value
---@param radio       table|nil  { freq, mod, volume, name, gender, culture, voice, googleTTS }
---@param shortMessage string|nil  Short version for TTS (falls back to message)
function ctld.utils.notifyCoalition(message, displayFor, side, radio, shortMessage)
    trigger.action.outTextForCoalition(side, message, displayFor)
    local short = shortMessage or message
    if STTS and STTS.TextToSpeech and radio and radio.freq then
        STTS.TextToSpeech(short, radio.freq, radio.mod or "FM", radio.volume or "1.0",
            radio.name or "JTAC", side, nil, 1, radio.gender or "male",
            radio.culture or "en-US", radio.voice, radio.googleTTS or false)
    else
        trigger.action.outSoundForCoalition(side, "radiobeep.ogg")
    end
end

--- Aggregates cargo weight from all managers for the given transport and
--- applies it as the DCS internal cargo weight (single authoritative call).
--- Replaces the independent per-manager setUnitInternalCargo calls to avoid
--- each manager overwriting the others.
--- DCS-native loaded crates/vehicles are excluded: DCS manages their weight.
--- @param unitName string  transport unit name
function ctld.utils.updateTransportWeight(unitName)
    local unit = Unit.getByName(unitName)
    if not (unit and unit:isExist()) then
        ctld.utils.log("INFO",
            "updateTransportWeight skipped — unit no longer exists: %s", unitName)
        return
    end
    local total = 0
    total = total + CTLDTroopManager.getInstance():getWeight(unitName)
    total = total + CTLDCrateManager.getInstance():getLoadedCrateWeight(unitName)
    total = total + CTLDVehicleSpawner.getInstance():getLoadedVehicleWeight(unitName)
    trigger.action.setUnitInternalCargo(unitName, total)
    ctld.utils.log("INFO",
        "updateTransportWeight %s = %d kg (troops+crates+vehicles)", unitName, total)
end

--- LUA PREDICATE helper: returns true after `duration` seconds from first call.
-- `key` must be unique per waypoint (e.g. "heliai_troops_wp2").
-- Usage in ME LUA PREDICATE field:
--   return ctld.utils.waitFor("heliai_troops_wp2", 15)
function ctld.utils.waitFor(key, duration)
    local gkey = "_waitFor_" .. key
    if not _G[gkey] then _G[gkey] = timer.getTime() end
    if timer.getTime() - _G[gkey] >= duration then
        _G[gkey] = nil
        return true
    end
    return false
end

-- ============================================================
-- ctld.scheduler  — central registry for long-running timer loops
-- ============================================================
-- Stores functionIds returned by timer.scheduleFunction so they can be
-- cancelled individually or all at once (e.g. before CTLD re-injection).
--
-- Usage:
--   local fid = timer.scheduleFunction(myLoop, nil, timer.getTime() + 5)
--   ctld.scheduler.register("my_loop_name", fid)
--
-- Shutdown (inject tests/dcs/util/shutdown_ctld.lua before re-injecting CTLD):
--   ctld.scheduler.cancelAll()
-- ============================================================

ctld.scheduler = {
    _ids = {}
}

--- Register a scheduled function by name. Cancels any previous loop with the
-- same name before storing the new ID (re-injection guard).
-- @param name       string   unique key (e.g. "beacon_refresh", "ai_transport")
-- @param functionId number   value returned by timer.scheduleFunction
function ctld.scheduler.register(name, functionId)
    if ctld.scheduler._ids[name] then
        pcall(timer.removeFunction, ctld.scheduler._ids[name])
    end
    ctld.scheduler._ids[name] = functionId
end

--- Cancel a single loop by name.
-- @param name string
function ctld.scheduler.cancel(name)
    if ctld.scheduler._ids[name] then
        pcall(timer.removeFunction, ctld.scheduler._ids[name])
        ctld.scheduler._ids[name] = nil
    end
end

--- Cancel all registered loops (call before re-injecting CTLD.lua).
function ctld.scheduler.cancelAll()
    local n = 0
    for name, fid in pairs(ctld.scheduler._ids) do
        pcall(timer.removeFunction, fid)
        ctld.scheduler._ids[name] = nil
        n = n + 1
    end
    ctld.utils.log("INFO", "ctld.scheduler.cancelAll: %d loop(s) cancelled", n)
end

-- =====================================================================
-- ctld.startupReport — init/config diagnostic collector
--
-- All managers feed this during ctld.initialize(). A single flush()
-- at end of init consolidates everything into DCS.log + one outText.
--
-- Family 1 (init/config):  ctld.startupReport.add()  — MM-facing.
-- Family 2 (runtime/dev):  ctld.utils.log()          — CTLD.log only.
-- Never mix the two families (ADR 0010).
-- =====================================================================
ctld.startupReport = {
    _entries = {},
}

--- Record a config/init diagnostic entry.
---@param severity string "ERROR", "NOTICE", or "INFO"
---@param source   string Human-readable manager name (e.g. "CrateManager")
---@param message  string Already-translated string (caller uses ctld.tr() at call site)
--
-- Severity semantics:
--   ERROR  — config incoherence; entry skipped or feature degraded. Triggers alarm outText.
--   NOTICE — non-blocking reminder (mod requirement, player-facing hint). Shown in full on screen.
--   INFO   — diagnostic info; written to DCS.log only, no screen output.
function ctld.startupReport.add(severity, source, message)
    local entries = ctld.startupReport._entries
    entries[#entries + 1] = { severity = severity, source = source, message = message }
end

--- Flush all collected entries to DCS.log and (when issues exist) to screen.
--- Always writes the CTLD_STARTUP_REPORT banner. Resets the collector afterwards.
--- [OK] is written only when the collector is completely empty (all severities).
function ctld.startupReport.flush()
    local entries = ctld.startupReport._entries
    ctld.startupReport._entries = {}

    -- Build log block (always written)
    local lines = { "=== CTLD_STARTUP_REPORT ===" }
    local hasError  = false
    local hasNotice = false
    local noticeLines = {}

    for _, e in ipairs(entries) do
        lines[#lines + 1] = string.format("[%s] %s: %s", e.severity, e.source, e.message)
        if e.severity == "ERROR" then
            hasError = true
        elseif e.severity == "NOTICE" then
            hasNotice = true
            noticeLines[#noticeLines + 1] = e.message
        end
        -- INFO entries are written to the log block above but do not affect screen output
    end

    if #entries == 0 then
        lines[#lines + 1] = "[OK] No issues detected."
    end

    env.info(table.concat(lines, "\n"))

    -- Screen outText (INFO entries never contribute here)
    if hasError then
        local screen = ""
        if hasNotice then
            screen = table.concat(noticeLines, "\n") .. "\n\n"
        end
        screen = screen .. ctld.tr("[CTLD] Config errors detected — search CTLD_STARTUP_REPORT in DCS.log")
        trigger.action.outText(screen, 30)
    elseif hasNotice then
        trigger.action.outText(table.concat(noticeLines, "\n"), 30)
    end
end
