--!nonstrict
-- features/Playlist: queue logic of the music player (order, shuffle, repeat), pure.

local Playlist = {}
Playlist.__index = Playlist

function Playlist.new(rng)
	return setmetatable({ _rng = rng or math.random, _order = {}, _pos = 0, _size = 0, shuffle = false, loop = "All" }, Playlist)
end

-- setSize(n): rebuilds the play order for n tracks keeping the current track when possible.
function Playlist:setSize(n, keepTrack)
	local current = self:current()
	self._size = n
	self._order = {}
	for i = 1, n do
		self._order[i] = i
	end
	if self.shuffle and n > 1 then
		for i = n, 2, -1 do
			local j = math.floor(self._rng() * i) + 1
			self._order[i], self._order[j] = self._order[j], self._order[i]
		end
	end
	self._pos = 0
	if keepTrack and current and current <= n then
		for p, track in ipairs(self._order) do
			if track == current then
				self._pos = p
			end
		end
	end
end

function Playlist:setShuffle(flag)
	if self.shuffle ~= flag then
		self.shuffle = flag
		self:setSize(self._size, true)
	end
end

function Playlist:size()
	return self._size
end

function Playlist:current()
	return self._order[self._pos]
end

-- jump(track): set the current track (1-based index into the playlist).
function Playlist:jump(track)
	if track < 1 or track > self._size then
		return false
	end
	for p, t in ipairs(self._order) do
		if t == track then
			self._pos = p
			return true
		end
	end
	return false
end

-- advance(reason) -> trackIndex|nil. reason: "next" (user) | "ended" (track finished)
function Playlist:advance(reason)
	if self._size == 0 then
		return nil
	end
	if reason == "ended" and self.loop == "One" then
		return self:current() or self._order[1]
	end
	local nextPos = self._pos + 1
	if nextPos > self._size then
		if self.loop == "Off" and reason == "ended" then
			return nil
		end
		nextPos = 1
		if self.shuffle then
			self:setSize(self._size, false)
		end
	end
	self._pos = nextPos
	return self._order[nextPos]
end

function Playlist:previous()
	if self._size == 0 then
		return nil
	end
	local p = self._pos - 1
	if p < 1 then
		p = self._size
	end
	self._pos = p
	return self._order[p]
end

return Playlist
