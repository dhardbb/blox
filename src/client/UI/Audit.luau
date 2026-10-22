--!strict
-- DEBUG_UI checks (PLAN.md "Because you cannot see the UI"): after a screen is
-- laid out, log its size and warn loudly about any button under 44 px or any
-- label whose text does not fit. Warnings start with "[270] UI audit" so tests
-- and agents can grep the Output for them.

local Audit = {}

-- Audits every visible GUI object under `root`. Returns the number of problems.
function Audit.run(root: Instance, label: string): number
	local problems = 0
	local function visible(inst: Instance): boolean
		local node: Instance? = inst
		while node and node ~= root do
			if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
				return false
			end
			node = node.Parent
		end
		return true
	end
	for _, inst in root:GetDescendants() do
		if inst:IsA("GuiButton") and visible(inst) then
			local size = (inst :: GuiButton).AbsoluteSize
			if size.Y < 44 - 0.5 then
				problems += 1
				warn(`[270] UI audit {label}: button {inst.Name} is {math.floor(size.Y)}px tall (min 44)`)
			end
		end
		if (inst:IsA("TextLabel") or inst:IsA("TextButton")) and visible(inst) then
			local text = inst :: any
			if text.Text ~= "" and not text.TextWrapped and not text.TextScaled and not text.TextFits then
				problems += 1
				warn(
					`[270] UI audit {label}: text "{string.sub(text.Text, 1, 30)}" in {inst.Name} is truncated`
				)
			end
		end
	end
	local size = if root:IsA("GuiObject") then (root :: GuiObject).AbsoluteSize else nil
	print(`[270] UI audit {label}: {problems} problem(s){if size then ` at {size}` else ""}`)
	return problems
end

return Audit
