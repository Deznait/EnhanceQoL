local AceGUI = LibStub("AceGUI-3.0")

--[[ DragTreeGroup - simple TreeGroup extension with drag-and-drop
     Dragging is started with a left-click while holding ALT.
     When the mouse is released over another entry, the widget fires
     an "OnDragDrop" callback with the source and target unique values.
]]

local Type, Version = "EQOL_DragTreeGroup", 1

local function Constructor()
	local tree = AceGUI:Create("TreeGroup")
	tree.type = Type

	if not tree.origCreateButton then tree.origCreateButton = tree.CreateButton end

	function tree:CreateButton()
		local btn = self:origCreateButton()
		local oldClick = btn:GetScript("OnClick")
		btn:SetScript("OnMouseDown", function(frame, button)
			if button == "LeftButton" and IsAltKeyDown() then
				frame.obj.dragSource = frame.uniquevalue
				frame.obj.dragging = true
			else
				if oldClick then oldClick(frame, button) end
			end
		end)
		btn:SetScript("OnMouseUp", function(frame, button)
			local obj = frame.obj
			if obj.dragging then
				obj.dragging = nil
				local src = obj.dragSource
				obj.dragSource = nil
				if src and frame.uniquevalue then obj:Fire("OnDragDrop", src, frame.uniquevalue) end
			else
				if oldClick then oldClick(frame, button) end
			end
		end)
		return btn
	end

	return tree
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
