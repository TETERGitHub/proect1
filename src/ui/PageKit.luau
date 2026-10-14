--!nonstrict
-- ui/PageKit: shared helpers for building pages (control generation from the schema, pooled data
-- lists, info rows, confirm-able reset buttons).
-- Depends on: Framework, Window, Theme, Settings, Notify, Maid, Pool, I18n.

local import = ...
local F = import("ui/Framework")
local Window = import("ui/Window")
local Theme = import("ui/Theme")
local Settings = import("core/Settings")
local Notify = import("core/Notify")
local Maid = import("core/Maid")
local Pool = import("core/Pool")
local I18n = import("core/I18n")

local Kit = {}

-- Helpers --------------------------------------------------------------------------------------------------------

local function notify(title, text, level)
	Notify.push({ title = title, text = text, level = level or "info" })
end

-- Is `id` the page the user is looking at right now? Live updaters skip hidden pages.
local function visible(id)
	return Window.isVisible() and Window.currentPage() == id and not Window.isMinimized()
end

-- Build the right control for a schema key.
local function auto(page, key, overrides)
	local def = Settings.schema(key)
	local o = overrides or {}
	if def.type == "bool" then
		return page:toggle({ key = key, label = o.label or def.label, desc = o.desc or def.desc })
	elseif def.type == "number" then
		return page:slider({ key = key, label = o.label, desc = o.desc, suffix = o.suffix, format = o.format })
	elseif def.type == "enum" then
		return page:enum({ key = key, label = o.label, desc = o.desc })
	elseif def.type == "color" then
		return page:color({ key = key, label = o.label, desc = o.desc })
	elseif def.type == "string" then
		local row, box = page:input({
			label = o.label or def.label, desc = o.desc or def.desc, text = Settings.get(key), width = o.width or 220,
			onSubmit = function(text)
				local ok, err = Settings.set(key, text, "ui")
				if not ok then
					notify(def.label, tostring(err), "warn")
				end
			end,
		})
		page.maid:Give(Settings.observe(key, function(v)
			if box.Text ~= v then
				box.Text = v
			end
		end))
		return row
	end
end

local function section(page, title, keys, overrides)
	page:section(title)
	for _, key in ipairs(keys) do
		auto(page, key, overrides and overrides[key])
	end
end

-- Reset-page button shown at the top of generated settings pages.
-- resetButton(page, module): a "Reset page" action in the page header (confirmed before anything changes)
local function resetButton(page, module)
page:addHeaderAction(I18n.t("btn.reset"), function()
	F.confirm({
		title = I18n.t("btn.reset"),
		text = "All settings of this page return to their defaults.",
		danger = true,
		onConfirm = function()
			local n = Settings.resetModule(module)
			notify(I18n.t("btn.reset"), I18n.t("notify.reset", n), "success")
		end,
	})
end, "danger", 112)
end

-- DataList: pooled rows with a title, sub-line, right-hand value and up to four icon buttons.
-- spec = {rowHeight, maxRows, buttons = { {icon, tip, fn(item)} }}
local function dataList(page, spec)
	-- one card holds the rows; hairlines separate them (see Page:openGroup for the same idea on settings pages)
	local holder = F.surface(page.content, "card", { name = "List", props = { LayoutOrder = page:nextOrder(), AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), Visible = false } })
	F.list(holder, 0)
	local height = spec.rowHeight or 46
	local buttons = spec.buttons or {}
	local pool = Pool.new({
		create = function()
			local row = Instance.new("Frame")
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, height)
			row.BackgroundTransparency = 1
			local div = F.frame(row, { Name = "Divider", Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 0, 1) }, { BackgroundColor3 = "stroke" })
			div.BackgroundTransparency = 0.72
			local rightPad = 12 + #buttons * 30
			local title = F.label(row, "", { size = 13, bold = true, dim = UDim2.new(1, -rightPad - 100, 0, 18) })
			title.Name = "Title"
			title.Position = UDim2.fromOffset(14, height > 40 and 7 or 0)
			if height <= 40 then
				title.Size = UDim2.new(1, -rightPad - 100, 1, 0)
			end
			local sub = F.label(row, "", { size = 11, token = "textDim", dim = UDim2.new(1, -rightPad - 100, 0, 14) })
			sub.Name = "Sub"
			sub.Position = UDim2.fromOffset(14, 26)
			local value = F.label(row, "", { size = 12, bold = true, token = "textDim", align = Enum.TextXAlignment.Right, dim = UDim2.fromOffset(96, 18) })
			value.Name = "Value"
			value.AnchorPoint = Vector2.new(1, 0.5)
			value.Position = UDim2.new(1, -rightPad, 0.5, 0)
			row:SetAttribute("built", true)
			return row
		end,
		reset = function(row)
			row.Parent = nil
		end,
		destroy = function(row)
			row:Destroy()
		end,
		max = spec.maxRows or 30,
	})
	local active = {}
	local rowMaids = {}
	local obj = {}

	local function release()
		for _, row in ipairs(active) do
			pool:Release(row)
		end
		table.clear(active)
		for _, m in ipairs(rowMaids) do
			m:Clean()
		end
		table.clear(rowMaids)
	end

	function obj.set(items)
		release()
		for i, item in ipairs(items) do
			if i > (spec.maxRows or 30) then
				break
			end
			local row = pool:Acquire()
			row.LayoutOrder = i
			row.Divider.Visible = i > 1
			-- raw items carry technical text (task names, log lines, keys) that must stay as written
			local tr = item.raw and function(t) return t end or I18n.tr
			row.Title.Text = tr(item.title or "")
			row.Sub.Text = tr(item.sub or "")
			row.Sub.Visible = (item.sub or "") ~= "" and height > 40
			row.Value.Text = item.rawValue and (item.value or "") or I18n.tr(item.value or "")
			Theme.bind(row.Value, "TextColor3", item.valueToken or "textDim")
			Theme.bind(row.Title, "TextColor3", item.titleToken or "text")
			local m = Maid.new("datalist-row")
			for bi, b in ipairs(buttons) do
				if (not b.show) or b.show(item) then
					local btn = F.iconButton(row, b.icon, function()
						b.fn(item)
					end, 26, m, b.token)
					btn.AnchorPoint = Vector2.new(1, 0.5)
					btn.Position = UDim2.new(1, -8 - (#buttons - bi) * 30, 0.5, 0)
					if b.tip then
						F.tooltip(btn, b.tip, m)
					end
					m:Give(btn)
				end
			end
			row.Parent = holder
			table.insert(active, row)
			table.insert(rowMaids, m)
			end
			holder.Visible = #active > 0
			end
			page.maid:Give(release)
	page.maid:Give(function()
		pool:Clear()
	end)
	obj.pool = pool
	obj.holder = holder
	return obj
end

local function infoLine(page, label, valueFn)
	local row, holder = page:row({ label = label, width = 200 })
	local v = F.label(holder, "", { size = 13, bold = true, token = "textDim", align = Enum.TextXAlignment.Right, dim = UDim2.fromOffset(200, 20) })
	v.AnchorPoint = Vector2.new(1, 0.5)
	v.Position = UDim2.fromScale(1, 0.5)
	return function()
		local text = I18n.tr(valueFn())
		if v.Text ~= text then
			v.Text = text
		end
	end, v
end


Kit.notify = notify
Kit.visible = visible
Kit.auto = auto
Kit.section = section
Kit.resetButton = resetButton
Kit.dataList = dataList
Kit.infoLine = infoLine

return Kit
