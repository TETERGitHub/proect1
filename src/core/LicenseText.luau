--!nonstrict
-- core/LicenseText: Russian texts for everything the user sees in the licence-key windows
-- (the loader's key window and the in-script gate). Known error messages from the verifier and the
-- server are translated; unknown ones are shown unchanged so nothing is hidden or invented.

local LicenseText = {}

LicenseText.UI = {
	title = "MM2 Hub",
	prompt = "Введите ключ лицензии, чтобы продолжить.",
	placeholder = "MM2H-XXXXX-XXXXX-...",
	button = "Активировать",
	checking = "Проверяю ключ…",
	valid = "Ключ принят. Осталось: ",
	failed = "Не удалось активировать ключ",
	pasteHint = "Вставьте ключ и нажмите Enter или кнопку ниже.",
}

local ERRORS = {
	["that does not look like a key"] = "Это не похоже на ключ. Проверьте, что вставили его целиком.",
	["could not reach the licence server"] = "Не удалось связаться с сервером лицензий. Проверьте интернет и адрес сервера.",
	["empty response from the licence server"] = "Сервер лицензий прислал пустой ответ.",
	["licence server sent an unreadable response"] = "Сервер лицензий прислал непонятный ответ.",
	["malformed payload from the licence server"] = "Сервер лицензий прислал повреждённые данные.",
	["invalid key"] = "Неверный ключ.",
	["invalid key (signature mismatch)"] = "Неверный ключ (подпись не совпадает).",
	["this key has been revoked"] = "Этот ключ отозван.",
	["key expired"] = "Срок действия ключа истёк.",
	["key is already bound to another account"] = "Этот ключ уже привязан к другому аккаунту.",
	["account id required"] = "Не удалось определить ваш аккаунт Roblox.",
	["key is not valid yet"] = "Ключ ещё не действует. Проверьте дату и время на устройстве.",
	["too many attempts, wait a minute"] = "Слишком много попыток. Подождите минуту.",
	["bad request"] = "Некорректный запрос.",
	["bad request size"] = "Некорректный запрос.",
	["not found"] = "Сервер не нашёл нужный адрес. Проверьте адрес сервера в загрузчике.",
	["key must be text"] = "Ключ должен быть текстом.",
	["not a MM2 Hub key (expected MM2H-...)"] = "Это не ключ MM2 Hub (ключ начинается с MM2H-).",
	["key contains invalid characters or is too short"] = "В ключе есть недопустимые символы, либо он слишком короткий.",
	["this build has no license secret configured"] = "В этой сборке не настроена проверка ключей.",
	["payload authentication failed (wrong key or tampered data)"] = "Не удалось проверить данные хаба: неверный ключ или данные повреждены.",
	["no key activated"] = "Ключ ещё не активирован.",
	["system clock was set back; refusing to run"] = "Системное время переведено назад. Исправьте время на устройстве.",
	["key is not valid yet (device clock appears to be behind)"] = "Ключ ещё не действует: время на устройстве отстаёт.",
}

local PREFIX_ERRORS = {
	{ "key expired ", "Срок действия ключа истёк " },
	{ "hub code failed to compile: ", "Код хаба не удалось скомпилировать: " },
	{ "hub failed to start: ", "Хаб не запустился: " },
	{ "unsupported key version", "Неподдерживаемая версия ключа" },
	{ "decode failed: ", "Не удалось прочитать ключ: " },
}

-- ru(message) -> Russian text, or the original message when it is not a known one.
function LicenseText.ru(message)
	if type(message) ~= "string" or message == "" then
		return "Неизвестная ошибка."
	end
	local known = ERRORS[message]
	if known then
		return known
	end
	for _, p in ipairs(PREFIX_ERRORS) do
		if string.sub(message, 1, #p[1]) == p[1] then
			return p[2] .. string.sub(message, #p[1] + 1)
		end
	end
	return message
end

local function plural(n, one, few, many)
	local m10, m100 = n % 10, n % 100
	if m10 == 1 and m100 ~= 11 then
		return one
	elseif m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then
		return few
	end
	return many
end

LicenseText.plural = plural

-- remaining(seconds) -> "29 дней 23 ч 59 мин" / "5 минут 3 с" / "срок истёк"
function LicenseText.remaining(seconds)
	seconds = math.floor(seconds)
	if seconds <= 0 then
		return "срок истёк"
	end
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if d > 0 then
		return string.format("%d %s %d ч %d мин", d, plural(d, "день", "дня", "дней"), h, m)
	elseif h > 0 then
		return string.format("%d ч %d мин %d с", h, m, s)
	elseif m > 0 then
		return string.format("%d %s %d с", m, plural(m, "минута", "минуты", "минут"), s)
	end
	return string.format("%d с", s)
end

return LicenseText
