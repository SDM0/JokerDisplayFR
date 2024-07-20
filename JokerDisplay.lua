--- STEAMODDED HEADER
--- MOD_NAME: JokerDisplay
--- MOD_ID: JokerDisplay
--- MOD_AUTHOR: [nh6574]
--- MOD_DESCRIPTION: Display useful information under Jokers. Right-click on a Joker/Display to hide/show. Left-click on a Display to collapse/expand.
--- PRIORITY: -100000
--- VERSION: 1.5.2

----------------------------------------------
------------MOD CODE -------------------------

---UTILITY FUNCTIONS

--- Splits text by a separator.
---@param str string String to split
---@param sep string? Separator. Defauls to whitespace.
---@return table split_text
local function strsplit(str, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for substr in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(t, substr)
    end
    return t
end

--- Deep copies a table
---@param orig table? Table to copy
---@return table? copy
local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

---MOD INITIALIZATION
local mod = SMODS.current_mod
JokerDisplay = {}

if SMODS["INIT"] then -- 0.9.x
    local init = SMODS["INIT"]
    function init.JokerDisplay()
        JokerDisplay.Path = (SMODS.findModByID and SMODS.findModByID('JokerDisplay').path)
        JokerDisplay.Definitions = NFS.load(JokerDisplay.Path .. "display_definitions.lua")() or {}
    end
else -- 1.x
    if SMODS.Atlas then
        SMODS.Atlas({
            key = "modicon",
            path = "icon.png",
            px = 32,
            py = 32
        })
    end
    JokerDisplay.Path = SMODS.current_mod.path
    JokerDisplay.Definitions = NFS.load(JokerDisplay.Path .. "display_definitions.lua")() or {}
end

---DISPLAY BOX CLASS

JokerDisplayBox = UIBox:extend()

function JokerDisplayBox:init(parent, func, args)
    args = args or {}

    args.definition = args.definition or {
        n = G.UIT.ROOT,
        config = {
            minh = 0.6,
            minw = 2,
            maxw = 2,
            r = 0.001,
            padding = 0.1,
            align = 'cm',
            colour = adjust_alpha(darken(G.C.BLACK, 0.2), 0.8),
            shadow = true,
            func = func,
            ref_table = parent
        },
        nodes = {
            {
                n = G.UIT.R,
                config = { ref_table = parent, align = "cm", func = "joker_display_style_override" },
                nodes = {
                    {
                        n = G.UIT.R,
                        config = { id = "modifiers", ref_table = parent, align = "cm" },
                    },
                    {
                        n = G.UIT.R,
                        config = { id = "extra", ref_table = parent, align = "cm" },
                    },
                    {
                        n = G.UIT.R,
                        config = { id = "text", ref_table = parent, align = "cm" },
                    },
                    {
                        n = G.UIT.R,
                        config = { id = "reminder_text", ref_table = parent, align = "cm" },
                    }
                }
            },
        }
    }

    args.config = args.config or {}
    args.config.align = args.config.align or "bm"
    args.config.parent = parent
    args.config.offset = { x = 0, y = -0.1 }

    UIBox.init(self, args)

    self.states.collide.can = true
    self.name = "JokerDisplay"
    self.joker_display_type = args.type or "NORMAL"
    self.can_collapse = true

    self.text = self.UIRoot.children[1].children[3]
    self.has_text = false
    self.reminder_text = self.UIRoot.children[1].children[4]
    self.has_reminder_text = false
    self.extra = self.UIRoot.children[1].children[2]
    self.has_extra = false
    self.modifier_row = self.UIRoot.children[1].children[1]
    self.has_modifiers = false

    self.modifiers = {
        chips = nil,
        x_chips = nil,
        x_chips_text = nil,
        mult = nil,
        x_mult = nil,
        x_mult_text = nil,
        dollars = nil,
    }
end

function JokerDisplayBox:recalculate()
    if not (self.has_text or self.has_extra or self.has_modifiers) and self.has_reminder_text then
        self.text.config.minh = 0.4
    else
        self.text.config.minh = nil
    end

    if self.has_text then
        self.text.config.padding = 0.03
    else
        self.text.config.padding = nil
    end

    UIBox.recalculate(self)
    self:align_to_text()
end

function JokerDisplayBox:add_text(nodes, config, custom_parent)
    self.has_text = true
    for i = 1, #nodes do
        self:add_child(JokerDisplay.create_display_object(custom_parent or self.parent, nodes[i], config), self.text)
    end
end

function JokerDisplayBox:remove_text()
    self.has_text = false
    self:remove_children(self.text)
end

function JokerDisplayBox:add_reminder_text(nodes, config, custom_parent)
    self.has_reminder_text = true
    for i = 1, #nodes do
        self:add_child(JokerDisplay.create_display_object(custom_parent or self.parent, nodes[i], config),
            self.reminder_text)
    end
end

function JokerDisplayBox:remove_reminder_text()
    self.has_reminder_text = false
    self:remove_children(self.reminder_text)
end

function JokerDisplayBox:add_extra(node_rows, config, custom_parent)
    self.has_extra = true
    for i = #node_rows, 1, -1 do
        local row_nodes = {}
        for j = 1, #node_rows[i] do
            table.insert(row_nodes,
                JokerDisplay.create_display_object(custom_parent or self.parent, node_rows[i][j], config))
        end
        local extra_row = {
            n = G.UIT.R,
            config = { ref_table = parent, align = "cm", padding = 0.03 },
            nodes = row_nodes
        }
        self:add_child(extra_row, self.extra)
    end
end

function JokerDisplayBox:remove_extra()
    self.has_extra = false
    self:remove_children(self.extra)
end

function JokerDisplayBox:change_modifiers(modifiers, reset)
    local new_modifiers = {
        chips = modifiers.chips, --or not reset and self.modifiers.chips or nil,
        x_chips = modifiers.x_chips, --or not reset and self.modifiers.x_chips or nil,
        mult = modifiers.mult, --or not reset and self.modifiers.mult or nil,
        x_mult = modifiers.x_mult, --or not reset and self.modifiers.x_mult or nil,
        dollars = modifiers.dollars, -- not reset and self.modifiers.dollars or nil,
    }

    local mod_keys = { "chips", "x_chips", "mult", "x_mult", "dollars" }
    local modifiers_changed = reset or false
    local has_modifiers = false

    for i = 1, #mod_keys do
        if (not not self.modifiers[mod_keys[i]]) ~= (not not new_modifiers[mod_keys[i]]) then
            modifiers_changed = true
        end
        self.modifiers[mod_keys[i]] = new_modifiers[mod_keys[i]]
        if self.modifiers[mod_keys[i]] then
            has_modifiers = true
        end
    end

    self.modifiers.x_chips_text = self.modifiers.x_chips and tonumber(string.format("%.2f", self.modifiers.x_chips)) or
        nil
    self.modifiers.x_mult_text = self.modifiers.x_mult and tonumber(string.format("%.2f", self.modifiers.x_mult)) or nil

    if modifiers_changed then
        self:remove_modifiers()
        if has_modifiers then
            self:add_modifiers()
        end
    end
end

function JokerDisplayBox:add_modifiers()
    self.has_modifiers = true

    local mod_nodes = {}

    if self.modifiers.chips then
        local chip_node = {}
        table.insert(chip_node, JokerDisplay.create_display_object(self, { text = "+", colour = G.C.CHIPS }))
        table.insert(chip_node,
            JokerDisplay.create_display_object(self,
                { ref_table = "card.modifiers", ref_value = "chips", colour = G.C.CHIPS }))
        table.insert(mod_nodes, chip_node)
    end

    if self.modifiers.x_chips then
        local xchip_node = {}
        table.insert(xchip_node,
            JokerDisplay.create_display_object(self,
                {
                    border_nodes = { { text = "X" },
                        { ref_table = "card.modifiers", ref_value = "x_chips_text" } },
                    border_colour = G.C.CHIPS
                }))
        table.insert(mod_nodes, xchip_node)
    end

    if self.modifiers.mult then
        local mult_node = {}
        table.insert(mult_node, JokerDisplay.create_display_object(self, { text = "+", colour = G.C.MULT }))
        table.insert(mult_node,
            JokerDisplay.create_display_object(self,
                { ref_table = "card.modifiers", ref_value = "mult", colour = G.C.MULT }))
        table.insert(mod_nodes, mult_node)
    end

    if self.modifiers.x_mult then
        local xmult_node = {}
        table.insert(xmult_node,
            JokerDisplay.create_display_object(self,
                {
                    border_nodes = {
                        { text = "X" },
                        { ref_table = "card.modifiers", ref_value = "x_mult_text" }
                    }
                }
            ))
        table.insert(mod_nodes, xmult_node)
    end

    if self.modifiers.dollars then
        local dollars_node = {}
        table.insert(dollars_node,
            JokerDisplay.create_display_object(self, { text = "+" .. localize('$'), colour = G.C.GOLD }))
        table.insert(dollars_node,
            JokerDisplay.create_display_object(self,
                { ref_table = "card.modifiers", ref_value = "dollars", colour = G.C.GOLD }))
        table.insert(mod_nodes, dollars_node)
    end

    local row_index = 1
    local mod_rows = {}
    for i = 1, #mod_nodes do
        if mod_rows[row_index] and #mod_rows[row_index] >= 2 then
            row_index = row_index + 1
        end
        if not mod_rows[row_index] then
            mod_rows[row_index] = {}
        end
        local mod_column = {
            n = G.UIT.C,
            config = { ref_table = parent, align = "cm", padding = 0.03 },
            nodes = mod_nodes[i]
        }
        table.insert(mod_rows[row_index], mod_column)
    end

    for i = 1, #mod_rows do
        local extra_row = {
            n = G.UIT.R,
            config = { ref_table = parent, align = "cm", padding = 0.03 },
            nodes = mod_rows[i]
        }
        self:add_child(extra_row, self.modifier_row)
    end
end

function JokerDisplayBox:remove_modifiers()
    self.has_modifiers = false
    self:remove_children(self.modifier_row)
end

function JokerDisplayBox:remove_children(node)
    if not node.children then
        return
    end
    remove_all(node.children)
    node.children = {}
    self:recalculate()
end

function JokerDisplayBox:align_to_text()
    local y_value = self.T and self.T.y - (self.has_text and self.text.T.y or
        self.has_extra and self.extra.children[#self.extra.children] and self.extra.children[#self.extra.children].T and self.extra.children[#self.extra.children].T.y or
        self.has_modifiers and self.modifier_row.children[#self.modifier_row.children] and self.modifier_row.children[#self.modifier_row.children].T and self.modifier_row.children[#self.modifier_row.children].T.y or
        (self.T.y - self.alignment.offset.y))
    self.alignment.offset.y = y_value or self.alignment.offset.y
end

function JokerDisplayBox:has_info()
    return self.has_text or self.has_extra or self.has_modifiers or self.has_reminder_text
end

---DISPLAY CONFIGURATION

---Updates the JokerDisplay and initializes it if necessary.
---@param force_update boolean? Force update even if disabled.
function Card:update_joker_display(force_update)
    if (mod.config.enabled or force_update) and self.ability and self.ability.set == 'Joker' and not self.no_ui and not G.debug_tooltip_toggle then
        if not self.children.joker_display then
            self.joker_display_values = {}
            self.joker_display_values.small = false

            --Regular Display
            self.children.joker_display = JokerDisplayBox(self, "joker_display_disable", { type = "NORMAL" })
            self.children.joker_display_small = JokerDisplayBox(self, "joker_display_small_enable", { type = "SMALL" })
            self.children.joker_display_debuff = JokerDisplayBox(self, "joker_display_debuff", { type = "DEBUFF" })
            self:initialize_joker_display()

            --Perishable Display
            self.config.joker_display_perishable = {
                n = G.UIT.ROOT,
                config = {
                    minh = 0.5,
                    maxh = 0.5,
                    minw = 0.75,
                    maxw = 0.75,
                    r = 0.001,
                    padding = 0.1,
                    align = 'cm',
                    colour = adjust_alpha(darken(G.C.BLACK, 0.2), 0.8),
                    shadow = false,
                    func = 'joker_display_perishable',
                    ref_table = self
                },
                nodes = {
                    {
                        n = G.UIT.R,
                        config = { align = "cm" },
                        nodes = { { n = G.UIT.R, config = { align = "cm" }, nodes = { JokerDisplay.create_display_text_object({ ref_table = self.joker_display_values, ref_value = "perishable", colour = lighten(G.C.PERISHABLE, 0.35), scale = 0.35 }) } } }
                    }

                }
            }

            self.config.joker_display_perishable_config = {
                align = "tl",
                bond = 'Strong',
                parent = self,
                offset = { x = 0.8, y = 0 },
            }
            if self.config.joker_display_perishable then
                self.children.joker_display_perishable = UIBox {
                    definition = self.config.joker_display_perishable,
                    config = self.config.joker_display_perishable_config,
                }
                self.children.joker_display_perishable.states.collide.can = true
                self.children.joker_display_perishable.name = "JokerDisplay"
            end

            --Rental Display
            self.config.joker_display_rental = {
                n = G.UIT.ROOT,
                config = {
                    minh = 0.5,
                    maxh = 0.5,
                    minw = 0.75,
                    maxw = 0.75,
                    r = 0.001,
                    padding = 0.1,
                    align = 'cm',
                    colour = adjust_alpha(darken(G.C.BLACK, 0.2), 0.8),
                    shadow = false,
                    func = 'joker_display_rental',
                    ref_table = self
                },
                nodes = {
                    {
                        n = G.UIT.R,
                        config = { align = "cm" },
                        nodes = { { n = G.UIT.R, config = { align = "cm" }, nodes = { JokerDisplay.create_display_text_object({ ref_table = self.joker_display_values, ref_value = "rental", colour = G.C.GOLD, scale = 0.35 }) } } }
                    }

                }
            }

            self.config.joker_display_rental_config = {
                align = "tr",
                bond = 'Strong',
                parent = self,
                offset = { x = -0.8, y = 0 },
            }
            if self.config.joker_display_rental then
                self.children.joker_display_rental = UIBox {
                    definition = self.config.joker_display_rental,
                    config = self.config.joker_display_rental_config,
                }
                self.children.joker_display_rental.states.collide.can = true
                self.children.joker_display_rental.name = "JokerDisplay"
            end
        else
            if mod.config.reload then
                self:initialize_joker_display()
                mod.config.reload = false
            else
                self:calculate_joker_display()
            end
        end
    end
end

---Updates the JokerDisplay for all jokers and initializes it if necessary.
---@param force_update boolean? Force update even if disabled.
function update_all_joker_display(force_update)
    if G.jokers then
        for k, v in pairs(G.jokers.cards) do
            v:update_joker_display(force_update)
        end
    end
end

function initialize_all_joker_display()
    if G.jokers then
        for k, v in pairs(G.jokers.cards) do
            v:initialize_joker_display()
        end
    end
end

function Card:joker_display_has_info()
    return (self.children.joker_display and self.children.joker_display:has_info()) or
        (self.children.joker_display_small and self.children.joker_display_small:has_info())
end

---STYLE MOD FUNCTIONS
G.FUNCS.joker_display_disable = function(e)
    local card = e.config.ref_table
    if card.facing == 'back' or card.debuff or card.joker_display_values.small or
        (not card:joker_display_has_info() and mod.config.hide_empty) then
        e.states.visible = false
        e.parent.states.collide.can = false
    else
        e.states.visible = mod.config.enabled
        e.parent.states.collide.can = mod.config.enabled
    end
end

G.FUNCS.joker_display_small_enable = function(e)
    local card = e.config.ref_table
    if card.facing == 'back' or card.debuff or not (card.joker_display_values.small) or
        (not card:joker_display_has_info() and mod.config.hide_empty) then
        e.states.visible = false
        e.parent.states.collide.can = false
    else
        e.states.visible = mod.config.enabled
        e.parent.states.collide.can = mod.config.enabled
    end
end


G.FUNCS.joker_display_debuff = function(e)
    local card = e.config.ref_table
    if not (card.facing == 'back') and card.debuff then
        e.states.visible = mod.config.enabled
        e.parent.states.collide.can = mod.config.enabled
    else
        e.states.visible = false
        e.parent.states.collide.can = false
    end
end

G.FUNCS.joker_display_perishable = function(e)
    local card = e.config.ref_table
    if not (card.facing == 'back') and card.ability.perishable then
        e.states.visible = mod.config.enabled
        e.parent.states.collide.can = mod.config.enabled
    else
        e.states.visible = false
        e.parent.states.collide.can = false
    end
end

G.FUNCS.joker_display_rental = function(e)
    local card = e.config.ref_table
    if not (card.facing == 'back') and card.ability.rental then
        e.states.visible = mod.config.enabled
        e.parent.states.collide.can = mod.config.enabled
    else
        e.states.visible = false
        e.parent.states.collide.can = false
    end
end

---Modifies JokerDisplay's nodes style values dynamically
---@param e table
G.FUNCS.joker_display_style_override = function(e)
    if mod.config.enabled then
        local card = e.config.ref_table
        local text = e.children and e.children[3] or nil
        local reminder_text = e.children and e.children[4] or nil
        local extra = e.children and e.children[2] or nil

        local is_blueprint_copying = card.joker_display_values and card.joker_display_values.blueprint_ability_key
        local joker_display_definition = JokerDisplay.Definitions[is_blueprint_copying or card.config.center.key]
        local style_function = joker_display_definition and joker_display_definition.style_function

        if style_function then
            local recalculate = style_function(card, text, reminder_text, extra)
            if recalculate then
                JokerDisplayBox.recalculate(e.UIBox)
            end
        end
    end
end

JokerDisplay.enable_disable = function()
    if not mod.config.enabled then
        update_all_joker_display(true)
    end
    mod.config.enabled = not mod.config.enabled
end

--HELPER FUNCTIONS

---Returns scoring information about a set of cards. Similar to _G.FUNCS.evaluate_play_.
---@param cards table Cards to calculate.
---@param count_facedowns boolean? If true, counts cards facing back.
---@return string text Scoring poker hand's non-localized text. "Unknown" if there's a card facedown.
---@return table poker_hands Poker hands contained in the scoring hand.
---@return table scoring_hand Scoring cards in hand.
JokerDisplay.evaluate_hand = function(cards, count_facedowns)
    local valid_cards = cards
    local has_facedown = false

    if not type(cards) == "table" then
        return "Unknown", {}, {}
    end
    for i = 1, #cards do
        if not type(cards[i]) == "table" or not (cards[i].ability.set == 'Enhanced' or cards[i].ability.set == 'Default') then
            return "Unknown", {}, {}
        end
    end

    if not count_facedowns then
        valid_cards = {}
        for i = 1, #cards do
            if cards[i].facing and not (cards[i].facing == 'back') then
                table.insert(valid_cards, cards[i])
            else
                has_facedown = true
            end
        end
    end

    local text, _, poker_hands, scoring_hand, _ = G.FUNCS.get_poker_hand_info(valid_cards)

    local pures = {}
    for i = 1, #valid_cards do
        if next(find_joker('Splash')) then
            scoring_hand[i] = valid_cards[i]
        else
            if valid_cards[i].ability.effect == 'Stone Card' then
                local inside = false
                for j = 1, #scoring_hand do
                    if scoring_hand[j] == valid_cards[i] then
                        inside = true
                    end
                end
                if not inside then table.insert(pures, valid_cards[i]) end
            end
        end
    end
    for i = 1, #pures do
        table.insert(scoring_hand, pures[i])
    end

    return (has_facedown and "Unknown" or text), poker_hands, scoring_hand
end

---Returns what Joker the current card (i.e. Blueprint or Brainstorm) is copying.
---@param card table Blueprint or Brainstorm card to calculate copy.
---@param _cycle_count integer? Counts how many times the function has recurred to prevent loops.
---@param _cycle_debuff boolean? Saves debuffed state on recursion.
---@return table|nil name Copied Joker
---@return boolean debuff If the copied joker (or any in the chain) is debuffed
JokerDisplay.calculate_blueprint_copy = function(card, _cycle_count, _cycle_debuff)
    if _cycle_count and _cycle_count > #G.jokers.cards + 1 then
        return nil, false
    end
    local other_joker = nil
    if card.ability.name == "Blueprint" then
        for i = 1, #G.jokers.cards do
            if G.jokers.cards[i] == card then
                other_joker = G.jokers.cards[i + 1]
            end
        end
    elseif card.ability.name == "Brainstorm" then
        other_joker = G.jokers.cards[1]
    end
    if other_joker and other_joker ~= card and other_joker.config.center.blueprint_compat then
        if other_joker.ability.name == "Blueprint" or other_joker.ability.name == "Brainstorm" then
            return JokerDisplay.calculate_blueprint_copy(other_joker,
                _cycle_count and _cycle_count + 1 or 1,
                _cycle_debuff or other_joker.debuff)
        else
            return other_joker, (_cycle_debuff or other_joker.debuff)
        end
    end
    return nil, false
end

---Returns all held instances of certain Joker, including Blueprint copies. Similar to _find_joker_.
---@param name string Name of the Joker to find.
---@param non_debuff boolean? If true also returns debuffed cards.
---@return table #All Jokers found, including Jokers with copy abilities.
JokerDisplay.find_joker_or_copy = function(name, non_debuff)
    local jokers = {}
    if not G.jokers or not G.jokers.cards then return {} end
    for k, v in pairs(G.jokers.cards) do
        if v and type(v) == 'table' and
            (v.ability.name == name or
                v.joker_display_values and v.joker_display_values.blueprint_ability_name and
                v.joker_display_values.blueprint_ability_name == name) and
            (non_debuff or not v.debuff) then
            table.insert(jokers, v)
        end
    end
    for k, v in pairs(G.consumeables.cards) do
        if v and type(v) == 'table' and
            (v.ability.name == name or
                v.joker_display_values and v.joker_display_values.blueprint_ability_name and
                v.joker_display_values.blueprint_ability_name == name) and
            (non_debuff or not v.debuff) then
            table.insert(jokers, v)
        end
    end

    local blueprint_count = 0
    for k, v in pairs(jokers) do
        if v.ability.name == "Blueprint" or v.ability.name == "Brainstorm" then
            blueprint_count = blueprint_count + 1
        end
    end
    if blueprint_count >= #jokers then
        return {}
    end

    return jokers
end

---Returns the leftmost card in a set of cards.
---@param cards table Cards to calculate.
---@return table|nil # Leftmost card in hand if any.
JokerDisplay.calculate_leftmost_card = function(cards)
    if not cards or type(cards) ~= "table" then
        return nil
    end
    local leftmost = cards[1]
    for i = 1, #cards do
        if cards[i].T.x < leftmost.T.x then
            leftmost = cards[i]
        end
    end
    return leftmost
end

---Returns how many times the scoring card would be triggered for scoring if played.
---@param card table Card to calculate.
---@param scoring_hand table? Scoring hand. nil if poker hand is unknown (i.e. there are facedowns) (This might change in the future).
---@param held_in_hand boolean? If the card is held in hand and not a scoring card.
---@return integer # Times the card would trigger. (0 if debuffed)
JokerDisplay.calculate_card_triggers = function(card, scoring_hand, held_in_hand)
    if card.debuff then
        return 0
    end

    local triggers = 1

    if G.jokers then
        for k, v in pairs(G.jokers.cards) do
            local joker_display_definition = JokerDisplay.Definitions[v.config.center.key]
            local retrigger_function = (not v.debuff and joker_display_definition and joker_display_definition.retrigger_function) or
                (not v.debuff and v.joker_display_values and v.joker_display_values.blueprint_ability_key and
                    not v.joker_display_values.blueprint_debuff and
                    JokerDisplay.Definitions[v.joker_display_values.blueprint_ability_key] and
                    JokerDisplay.Definitions[v.joker_display_values.blueprint_ability_key].retrigger_function)

            if retrigger_function then
                triggers = triggers + retrigger_function(card, scoring_hand, held_in_hand)
            end
        end
    end

    triggers = triggers + (card:get_seal() == 'Red' and 1 or 0)

    return triggers
end

JokerDisplay.calculate_joker_modifiers = function(card)
    local modifiers = {
        chips = nil,
        x_chips = nil,
        mult = nil,
        x_mult = nil,
        dollars = nil
    }
    local joker_edition = card:get_edition()

    if joker_edition and not card.debuff then
        modifiers.chips = joker_edition.chip_mod
        modifiers.mult = joker_edition.mult_mod
        modifiers.x_mult = joker_edition.x_mult_mod
    end

    if G.jokers then
        for k, v in pairs(G.jokers.cards) do
            local joker_display_definition = JokerDisplay.Definitions[v.config.center.key]
            local mod_function = (not v.debuff and joker_display_definition and joker_display_definition.mod_function) or
                (not v.debuff and v.joker_display_values and v.joker_display_values.blueprint_ability_key and
                    not v.joker_display_values.blueprint_debuff and
                    JokerDisplay.Definitions[v.joker_display_values.blueprint_ability_key] and
                    JokerDisplay.Definitions[v.joker_display_values.blueprint_ability_key].mod_function)

            if mod_function then
                local extra_mods = mod_function(card)
                modifiers = {
                    chips = modifiers.chips and extra_mods.chips and modifiers.chips + extra_mods.chips or
                        extra_mods.chips or modifiers.chips,
                    x_chips = modifiers.x_chips and extra_mods.x_chips and modifiers.x_chips * extra_mods.x_chips or
                        extra_mods.x_chips or modifiers.x_chips,
                    mult = modifiers.mult and extra_mods.mult and modifiers.mult + extra_mods.mult or
                        extra_mods.mult or modifiers.mult,
                    x_mult = modifiers.x_mult and extra_mods.x_mult and modifiers.x_mult * extra_mods.x_mult or
                        extra_mods.x_mult or modifiers.x_mult,
                    dollars = modifiers.dollars and extra_mods.dollars and modifiers.dollars + extra_mods.dollars or
                        extra_mods.dollars or modifiers.dollars,
                }
            end
        end
    end

    return modifiers
end

---Creates an object with JokerDisplay configurations.
---@param card table Reference card
---@param display_config {text: string?, ref_table: string?, ref_value: string?, scale: number?, colour: table?, border_nodes: table?, border_colour: table?, dynatext: table?} Node configuration
---@param defaults_config? {colour: table?, scale: number?} Defaults for all text objects
---@return table
JokerDisplay.create_display_object = function(card, display_config, defaults_config)
    local default_text_colour = defaults_config and defaults_config.colour or G.C.UI.TEXT_LIGHT
    local default_text_scale = defaults_config and defaults_config.scale or 0.4

    local node = {}
    if display_config.dynatext then
        return {
            n = G.UIT.O,
            config = {
                object = DynaText(
                    deepcopy(display_config.dynatext)
                )
            }
        }
    end
    if display_config.border_nodes then
        local inside_nodes = {}
        for i = 1, #display_config.border_nodes do
            table.insert(inside_nodes,
                JokerDisplay.create_display_object(card, display_config.border_nodes[i], defaults_config))
        end
        return JokerDisplay.create_display_border_text_object(inside_nodes, display_config.border_colour or G.C.XMULT)
    end
    if display_config.ref_value and display_config.ref_table then
        local table_path = strsplit(display_config.ref_table, ".")
        local ref_table = table_path[1] == "card" and card or _G[table_path[1]]
        for i = 2, #table_path do
            if ref_table[table_path[i]] then
                ref_table = ref_table[table_path[i]]
            end
        end
        return JokerDisplay.create_display_text_object({
            ref_table = ref_table,
            ref_value = display_config.ref_value,
            colour = display_config.colour or default_text_colour,
            scale = display_config.scale or default_text_scale
        })
    end
    if display_config.text then
        return JokerDisplay.create_display_text_object({
            text = display_config.text,
            colour = display_config.colour or default_text_colour,
            scale = display_config.scale or default_text_scale
        })
    end
    return node
end

---Creates a G.UIT.T object with JokerDisplay configurations for text display.
---@param config {text: string?, ref_table: table?, ref_value: string?, scale: number?, colour: table?}
---@return table
JokerDisplay.create_display_text_object = function(config)
    local text_node = {}
    if config.ref_table then
        text_node = { n = G.UIT.T, config = { ref_table = config.ref_table, ref_value = config.ref_value, scale = config.scale or 0.4, colour = config.colour or G.C.UI.TEXT_LIGHT } }
    else
        text_node = { n = G.UIT.T, config = { text = config.text or "ERROR", scale = config.scale or 0.4, colour = config.colour or G.C.UI.TEXT_LIGHT } }
    end
    return text_node
end

---Creates a G.UIT.C object with JokerDisplay configurations for text borders (e.g. for XMULT).
---@param nodes table Nodes contained inside the border.
---@param border_color table Color of the border.
---@return table
JokerDisplay.create_display_border_text_object = function(nodes, border_color)
    return {
        n = G.UIT.C,
        config = { colour = border_color, r = 0.05, padding = 0.03, res = 0.15 },
        nodes = nodes
    }
end

---DISPLAY DEFINITION

---Initializes nodes for JokerDisplay.
function Card:initialize_joker_display(custom_parent)
    if not custom_parent then
        self.children.joker_display:remove_text()
        self.children.joker_display:remove_reminder_text()
        self.children.joker_display:remove_extra()
        self.children.joker_display:remove_modifiers()
        self.children.joker_display_small:remove_text()
        self.children.joker_display_small:remove_reminder_text()
        self.children.joker_display_small:remove_extra()
        self.children.joker_display_small:remove_modifiers()
        self.children.joker_display_debuff:remove_text()
        self.children.joker_display_debuff:remove_modifiers()

        self.children.joker_display_debuff:add_text({ { text = "" .. localize("k_debuffed"), colour = G.C.UI.TEXT_INACTIVE } })
    end

    self:calculate_joker_display()

    local joker_display_definition = JokerDisplay.Definitions[self.config.center.key]
    local definiton_text = joker_display_definition and
        (joker_display_definition.text or joker_display_definition.line_1)
    local text_config = joker_display_definition and joker_display_definition.text_config
    local definiton_reminder_text = joker_display_definition and (joker_display_definition.reminder_text or
        joker_display_definition.line_2)
    local reminder_text_config = joker_display_definition and joker_display_definition.reminder_text_config
    local definiton_extra = joker_display_definition and joker_display_definition.extra
    local extra_config = joker_display_definition and joker_display_definition.extra_config

    if definiton_text then
        if custom_parent then
            custom_parent.children.joker_display:add_text(definiton_text, text_config, self)
            custom_parent.children.joker_display_small:add_text(definiton_text, text_config, self)
        else
            self.children.joker_display:add_text(definiton_text, text_config)
            self.children.joker_display_small:add_text(definiton_text, text_config)
        end
    end
    if definiton_reminder_text then
        if not reminder_text_config then
            reminder_text_config = {}
        end
        reminder_text_config.colour = reminder_text_config.colour or G.C.UI.TEXT_INACTIVE
        reminder_text_config.scale = reminder_text_config.scale or 0.3
        if mod.config.default_rows.reminder then
            if custom_parent then
                custom_parent.children.joker_display:add_reminder_text(definiton_reminder_text, reminder_text_config,
                    self)
            else
                self.children.joker_display:add_reminder_text(definiton_reminder_text, reminder_text_config)
            end
        end
        if mod.config.small_rows.reminder then
            if custom_parent then
                custom_parent.children.joker_display_small:add_reminder_text(definiton_reminder_text,
                    reminder_text_config, self)
            else
                self.children.joker_display_small:add_reminder_text(definiton_reminder_text, reminder_text_config)
            end
        end
    end
    if definiton_extra then
        if mod.config.default_rows.extra then
            if custom_parent then
                custom_parent.children.joker_display:add_extra(definiton_extra, extra_config, self)
            else
                self.children.joker_display:add_extra(definiton_extra, extra_config)
            end
        end
        if mod.config.small_rows.extra then
            if custom_parent then
                custom_parent.children.joker_display_small:add_extra(definiton_extra, extra_config, self)
            else
                self.children.joker_display_small:add_extra(definiton_extra, extra_config)
            end
        end
    end

    if custom_parent then
        custom_parent.children.joker_display:recalculate()
        custom_parent.children.joker_display_small:recalculate()
    else
        self.children.joker_display:recalculate()
        self.children.joker_display_small:recalculate()
    end
end

---DISPLAY CALCULATION

---Calculates values for JokerDisplay. Saves them to Card.joker_display_values.
function Card:calculate_joker_display()
    self.joker_display_values.perishable = (G.GAME.perishable_rounds or 5) .. "/" .. (G.GAME.perishable_rounds or 5)
    self.joker_display_values.rental = "-$" .. (G.GAME.rental_rate or 3)

    if self.ability.perishable then
        self.joker_display_values.perishable = (self.ability.perish_tally or 5) .. "/" .. (G.GAME.perishable_rounds or 5)
    end

    if self.ability.rental then
        self.joker_display_values.rental = "-$" .. (G.GAME.rental_rate or 3)
    end

    if mod.config.default_rows.modifiers then
        self.children.joker_display:change_modifiers(JokerDisplay.calculate_joker_modifiers(self), true)
        self.children.joker_display_debuff:change_modifiers(JokerDisplay.calculate_joker_modifiers(self), true)
    end

    if mod.config.small_rows.modifiers then
        self.children.joker_display_small:change_modifiers(JokerDisplay.calculate_joker_modifiers(self), true)
    end

    local joker_display_definition = JokerDisplay.Definitions[self.config.center.key]
    local calc_function = joker_display_definition and joker_display_definition.calc_function

    if calc_function then
        calc_function(self)
    end
end

--- UPDATE CONDITIONS

local node_stop_drag_ref = Node.stop_drag
function Node:stop_drag()
    node_stop_drag_ref(self)
    update_all_joker_display("Node.stop_drag")
end

local cardarea_emplace_ref = CardArea.emplace
function CardArea:emplace(card, location, stay_flipped)
    cardarea_emplace_ref(self, card, location, stay_flipped)
    update_all_joker_display("CardArea.emplace")
end

local cardarea_load_ref = CardArea.load
function CardArea:load(cardAreaTable)
    cardarea_load_ref(self, cardAreaTable)
    if self == G.jokers then
        update_all_joker_display("CardArea.load")
    end
end

local cardarea_parse_highlighted_ref = CardArea.parse_highlighted
function CardArea:parse_highlighted()
    cardarea_parse_highlighted_ref(self)
    update_all_joker_display("CardArea.parse_highlighted")
end

local cardarea_remove_card_ref = CardArea.remove_card
function CardArea:remove_card(card, discarded_only)
    local t = cardarea_remove_card_ref(self, card, discarded_only)
    update_all_joker_display("CardArea.remove_card")
    return t
end

local card_calculate_joker_ref = Card.calculate_joker
function Card:calculate_joker(context)
    local t = card_calculate_joker_ref(self, context)

    if G.jokers and self.area == G.jokers then
        self:update_joker_display("Card.calculate_joker")
    end
    return t
end

--- CONTROLLER INPUT

local controller_queue_R_cursor_press_ref = Controller.queue_R_cursor_press
function Controller:queue_R_cursor_press(x, y)
    controller_queue_R_cursor_press_ref(self, x, y)
    local press_node = self.hovering.target or self.focused.target
    if not G.SETTINGS.paused then
        if press_node and G.jokers and ((press_node.area and press_node.area == G.jokers)
                or (press_node.name and press_node.name == "JokerDisplay")) then
            JokerDisplay.enable_disable()
        end
    else
        if press_node and (press_node.area or (press_node.name and press_node.name == "JokerDisplay")) then
            JokerDisplay.visible = not JokerDisplay.visible
        end 
    end
end

local controller_queue_L_cursor_press_ref = Controller.queue_L_cursor_press
function Controller:queue_L_cursor_press(x, y)
    controller_queue_L_cursor_press_ref(self, x, y)
        local press_node = self.hovering.target or self.focused.target
        if press_node and press_node.name and press_node.name == "JokerDisplay" and press_node.can_collapse and press_node.parent then
            press_node.parent.joker_display_values.small = not press_node.parent.joker_display_values.small
        end
    
end

local controller_button_press_update_ref = Controller.button_press_update
function Controller:button_press_update(button, dt)
    controller_button_press_update_ref(self, button, dt)

    if button == 'b' and G.jokers and self.focused.target and self.focused.target.area == G.jokers then
        JokerDisplay.enable_disable()
    end
end

SMODS.current_mod.config_tab = function()
    -- Create a card area that will display an example joker
    G.config_card_area = CardArea(G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h, 1.03 * G.CARD_W, 1.03 * G.CARD_H,
                            {card_limit = 1, type = 'title', highlight_limit = 0,})
        local center = G.P_CENTERS['j_bloodstone']
        local card = Card(G.config_card_area.T.x + G.config_card_area.T.w/2, G.config_card_area.T.y, G.CARD_W, G.CARD_H, nil, center)
        card:set_edition('e_foil', true, true)
        G.config_card_area:emplace(card)
        G.config_card_area.cards[1]:update_joker_display()

    return {n = G.UIT.ROOT, config = {r = 0.1, minw = 8, align = "tm", padding = 0.2, colour = G.C.BLACK}, nodes = {
            {n = G.UIT.R, config = {align = "cm", padding = 0.07}, nodes = {
                create_toggle({label = localize('jdis_enabled'), ref_table = mod.config, ref_value = 'enabled'})
            }},
            {n = G.UIT.R, config = {padding = 0.2, align = "cm"}, nodes = {
                create_toggle({label = localize('jdis_hide_display'), ref_table = mod.config, ref_value = 'hide_empty'})
            }},
            {n = G.UIT.R, config = {padding = 0.2}, nodes = {
                {n = G.UIT.C, config = {align = "cm"}, nodes = {
                    {n = G.UIT.R, config = {align = "cm"}, nodes = {
                        {n = G.UIT.C, config = {align = "cr", padding = 0.2}, nodes = {
                            {n = G.UIT.R, config = {align = "cm"}, nodes = {
                                {n = G.UIT.T, config = {text = localize('jdis_default_display'), colour = G.C.UI.TEXT_LIGHT, scale = 0.5, align = "cr"}},
                            }},
                            create_toggle({label = localize('jdis_modifiers'), ref_table = mod.config.default_rows, callback = update_display, ref_value = 'modifiers', w = 2}),
                            create_toggle({label = localize('jdis_reminders'), ref_table = mod.config.default_rows, callback = update_display, ref_value = 'reminder', w = 2}),
                            create_toggle({label = localize('jdis_extras'), ref_table = mod.config.default_rows, callback = update_display, ref_value = 'extra', w = 2})
                        }},
                        {n = G.UIT.C, config = {align = "cr", padding = 0.2}, nodes = {
                            {n = G.UIT.R, config = {align = "cm"}, nodes = {
                                {n = G.UIT.T, config = {text = localize('jdis_small_display'), colour = G.C.UI.TEXT_LIGHT, scale = 0.5, align = "cr"}},
                            }},
                            create_toggle({label = localize('jdis_modifiers'), ref_table = mod.config.small_rows, callback = update_display, ref_value = 'modifiers', w = 2}),
                            create_toggle({label = localize('jdis_reminders'), ref_table = mod.config.small_rows, callback = update_display, ref_value = 'reminder', w = 2}),
                            create_toggle({label = localize('jdis_extras'), ref_table = mod.config.small_rows, callback = update_display, ref_value = 'extra', w = 2})
                        }}
                    }}
                }},
                {n = G.UIT.C, config = {align = "tm", padding = 0.1, no_fill = true}, nodes = {
                    {n = G.UIT.O, config = {object = G.config_card_area}}
                }}            
            }},
            {n = G.UIT.R, config = {minh = 0.5}}
        }}
end

-- Callback function for config toggles, updates the example joker and any current jokers if a game is being played
function update_display(value)
    mod.config.reload = true
    G.config_card_area.cards[1]:update_joker_display()
    if G.jokers then
        for _, joker in pairs(G.jokers.cards) do
            mod.config.reload = true
            joker:update_joker_display()
        end
    end
end

----------------------------------------------
------------MOD CODE END----------------------
