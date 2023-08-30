local function printUsage()
  local programName = arg[0] or fs.getName(shell.getRunningProgram())
  print("Usage:")
  print(programName .. " [loop] [random] <url>")
end

local args = { ... }

local loop = false
if args[1] == "loop" then
  table.remove(args, 1)
  loop = true
end

local random = false
if args[1] == "random" then
  table.remove(args, 1)
  random = true
end

if #args ~= 1 then
  printUsage()
  return
end

local song = table.remove(args, 1)
local url = require "song-links" [song] or song

if not http then
  printError("play requires the http API")
  printError("Set http.enabled to true in CC: Tweaked's config")
  return
end

local function get(sUrl)
  -- Check if the URL is valid
  local ok, err = http.checkURL(url)
  if not ok then
    printError(err or "Invalid URL.")
    return
  end

  return assert(http.get(sUrl, nil, true))
end

local events = {
  speaker_audio_empty = function()
    return true
  end,
  key = function(key)
  end,
}

local function processEvent(name, ...)
  local event = events[name]
  if event then
    return event(...)
  end
end

local function render()
  term.clear()
  term.setCursorPos(1, 1)
end

local response = get(url)
local data = response.readAll()
response:close()

local speakers = {}
for _, side in ipairs(peripheral.getNames()) do
  if peripheral.getType(side) == "speaker" then
    table.insert(speakers, peripheral.wrap(side))
  end
end
if #speakers == 0 then
  printError("No speakers found.")
  return
end

local redstoneSide = "back"  -- The side where your redstone line is connected

local dfpwm = require("cc.audio.dfpwm")
local decoder = dfpwm.make_decoder()

local bufferSize = 4 * 1024 - 1  -- Adjust buffer size as needed

local function quadrupleBytes(decodedAudio)
  local quadrupledAudio = {}
  for i = 1, #decodedAudio do
    local byteValue = decodedAudio[i]
    for _ = 1, 4 do
      quadrupledAudio[#quadrupledAudio + 1] = byteValue
    end
  end
  return quadrupledAudio
end

local function skipEverySecondByte(audioData)
  local trimmedAudio = {}
  for i = 1, #audioData, 2 do
    trimmedAudio[#trimmedAudio + 1] = audioData[i]
  end
  return trimmedAudio
end

local function playAudioOnAllSpeakers(audioBuffer)
  for _, speaker in ipairs(speakers) do
    while not speaker.playAudio(audioBuffer) do
      sleep(2)  -- Add a short delay if needed
    end
  end
end

local dataBytes = { data:byte(1, #data) } -- Convert data to a byte array
local pos = random and math.random(1, #dataBytes) or 1

repeat
  while pos <= #dataBytes do
    local endPos = math.min(pos + bufferSize - 1, #dataBytes)
    local chunk = {}
    for i = pos, endPos do
      chunk[#chunk + 1] = dataBytes[i]
    end
    pos = endPos + 1
    local decodedChunk = decoder(string.char(table.unpack(chunk)))

    local quadrupledBuffer = quadrupleBytes(decodedChunk)
    local trimmedBuffer = skipEverySecondByte(quadrupledBuffer)

    local audioBuffer = table.pack(table.unpack(trimmedBuffer))
    playAudioOnAllSpeakers(audioBuffer)
  end
  pos = 1
until not loop
