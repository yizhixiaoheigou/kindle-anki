-- The "Import via browser" screen: the page address as a QR code and as
-- text, the pairing code, and Keep running / Stop now.
--
-- Built from KOReader's own widgets (QRWidget exists since 2023). main.lua
-- builds it inside pcall and falls back to a plain ConfirmBox, so a widget
-- API difference on some KOReader build degrades to text, never a crash.

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local QRWidget = require("ui/widget/qrwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local ImportDialog = InputContainer:extend{
    modal = true,
    title = nil,
    lead = nil,       -- one line above the QR code
    url = nil,        -- the address shown as text
    qr_text = nil,    -- what the QR code encodes; defaults to url
    show_qr = true,
    notes = nil,      -- list of paragraphs under the address
    keep_text = nil,
    stop_text = nil,
    on_keep = nil,
    on_stop = nil,
}

function ImportDialog:init()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    local width = math.floor(Screen:getWidth() * 0.88)
    local padding = Size.padding.large
    local inner = width - 2 * padding
    local gap = Screen:scaleBySize(12)

    local function text(value, face, alignment)
        return TextBoxWidget:new{
            text = value,
            face = face,
            width = inner,
            alignment = alignment or "center",
        }
    end

    local group = VerticalGroup:new{ align = "center" }
    table.insert(group, text(self.title, Font:getFace("tfont", 22)))
    table.insert(group, VerticalSpan:new{ width = gap })
    table.insert(group, text(self.lead, Font:getFace("cfont", 18)))
    if self.show_qr then
        -- About a third of the screen height: big enough for a phone to
        -- read off e-ink at arm's length, small enough to keep the buttons.
        local qr_size = math.floor(math.min(inner * 0.75, Screen:getHeight() * 0.32))
        table.insert(group, VerticalSpan:new{ width = gap })
        table.insert(group, QRWidget:new{ text = self.qr_text or self.url, width = qr_size, height = qr_size })
    end
    table.insert(group, VerticalSpan:new{ width = gap })
    table.insert(group, text(self.url, Font:getFace("tfont", 24)))
    for _index, note in ipairs(self.notes or {}) do
        table.insert(group, VerticalSpan:new{ width = gap })
        table.insert(group, text(note, Font:getFace("cfont", 17), "left"))
    end
    table.insert(group, VerticalSpan:new{ width = gap })
    table.insert(group, ButtonTable:new{
        width = inner,
        buttons = {{
            { text = self.keep_text, callback = function() self:close(self.on_keep) end },
            { text = self.stop_text, callback = function() self:close(self.on_stop) end },
        }},
        zero_sep = true,
        show_parent = self,
    })

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = padding,
        group,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.frame,
    }
end

function ImportDialog:close(action)
    UIManager:close(self)
    if action then action() end
end

function ImportDialog:onClose()
    self:close(self.on_keep)
    return true
end

function ImportDialog:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

function ImportDialog:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen end)
end

return ImportDialog
