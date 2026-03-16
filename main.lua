-- HeldJoker mod
-- Allows the player to hold one joker from the shop in a special slot.
-- The held joker can be added to your joker row for free, or sold (unless Eternal).

local HJ = {}
HJ.SCALE = 0.47

-- ─── Persistence helpers ─────────────────────────────────────────────────────

local function edition_to_str(card)
    if not card.edition then return nil end
    if card.edition.key then
        return card.edition.key:gsub('^e_', '')
    end
    for k, v in pairs(card.edition) do
        if v == true then return k end
    end
    return nil
end

local function save_held_data(card)
    G.GAME.hj_held_data = {
        center_key = card.config.center.key,
        edition    = edition_to_str(card),
        cost       = card.cost,
        sell_cost  = card.sell_cost,
        eternal    = card.ability.eternal    or nil,
        perishable = card.ability.perishable or nil,
        rental     = card.ability.rental     or nil,
    }
end

-- ─── Shop UI ─────────────────────────────────────────────────────────────────

local orig_shop_uidef = G.UIDEF.shop
G.UIDEF.shop = function()
    local s = HJ.SCALE

    G.hj_held_area = CardArea(
        G.hand.T.x, G.hand.T.y,
        G.CARD_W * s * 1.1,
        G.CARD_H * s * 1.05,
        { card_limit = 1, type = 'shop', highlight_limit = 1,
          card_w = G.CARD_W * s,
          align_buttons = true, no_card_count = true }
    )

    if G.GAME.hj_held_data then
        local data   = G.GAME.hj_held_data
        local center = G.P_CENTERS[data.center_key]
        if center then
            local card = Card(
                G.hj_held_area.T.x + G.hj_held_area.T.w / 2,
                G.hj_held_area.T.y,
                G.CARD_W * s, G.CARD_H * s,
                G.P_CARDS.empty, center,
                { bypass_discovery_center = true, bypass_discovery_ui = true }
            )
            if data.edition then
                card:set_edition({ [data.edition] = true }, true)
            end
            card.ability.eternal    = data.eternal
            card.ability.perishable = data.perishable
            card.ability.rental     = data.rental
            card.cost      = data.cost
            card.sell_cost = data.sell_cost
            card:start_materialize()
            G.hj_held_area:emplace(card)
            HJ.create_held_card_ui(card)
        else
            G.GAME.hj_held_data = nil
        end
    end

    local t = orig_shop_uidef()

    -- Create a standalone floating UIBox anchored to the consumable area
    -- so it doesn't affect the shop layout at all.
    if G.hj_held_box then
        G.hj_held_box:remove()
        G.hj_held_box = nil
    end

    G.hj_held_box = UIBox {
        definition = {
            n = G.UIT.ROOT,
            config = { align = "cm", colour = G.C.L_BLACK, r = 0.1,
                       padding = 0.08, emboss = 0.05 },
            nodes = {
                { n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
                    { n = G.UIT.T, config = { text = "Held", scale = 0.28,
                                              colour = G.C.WHITE, shadow = true } }
                }},
                { n = G.UIT.R, config = { align = "cm", padding = 0.03 }, nodes = {
                    { n = G.UIT.O, config = { object = G.hj_held_area } }
                }}
            }
        },
        config = {
            align = 'cr',
            offset = { x = 0.3, y = 0 },
            major = G.consumeables,
            bond = 'Weak',
        }
    }

    -- Auto-remove the floating box when the shop closes.
    G.E_MANAGER:add_event(Event({
        trigger   = 'after',
        delay     = 0.5,
        blocking  = false,
        blockable = false,
        func = function()
            if G.hj_held_box and not G.shop then
                G.hj_held_box:remove()
                G.hj_held_box = nil
                return true
            end
            return G.hj_held_box == nil
        end
    }))

    return t
end

-- ─── DrawSteps ───────────────────────────────────────────────────────────────

SMODS.draw_ignore_keys['hj_hold_button'] = true
SMODS.draw_ignore_keys['hj_sell_price']  = true
SMODS.draw_ignore_keys['hj_add_button']  = true
SMODS.draw_ignore_keys['hj_sell_button'] = true

SMODS.DrawStep {
    key   = 'hj_buttons',
    order = -29,
    func  = function(self)
        if self.children.hj_hold_button then
            if self.highlighted
               and (self.area == G.shop_jokers
                    or (G.pack_cards and self.area == G.pack_cards)) then
                self.children.hj_hold_button.states.visible = true
                self.children.hj_hold_button:draw()
            else
                self.children.hj_hold_button.states.visible = false
            end
        end

        if self.children.hj_sell_price then
            if self.highlighted and G.hj_held_area
               and self.area == G.hj_held_area then
                self.children.hj_sell_price.states.visible = true
                self.children.hj_sell_price:draw()
            else
                self.children.hj_sell_price.states.visible = false
            end
        end

        if self.children.hj_add_button then
            if self.highlighted and G.hj_held_area
               and self.area == G.hj_held_area then
                self.children.hj_add_button.states.visible = true
                self.children.hj_add_button:draw()
                if self.children.hj_sell_button then
                    self.children.hj_sell_button.states.visible = true
                    self.children.hj_sell_button:draw()
                end
            else
                self.children.hj_add_button.states.visible = false
                if self.children.hj_sell_button then
                    self.children.hj_sell_button.states.visible = false
                end
            end
        end
    end,
}

-- ─── Hold button injection ────────────────────────────────────────────────────

function HJ.inject_hold_button(card)
    G.E_MANAGER:add_event(Event({
        trigger   = 'after',
        delay     = 0.43,
        blocking  = false,
        blockable = false,
        func = function()
            if card.removed then return true end
            if card.children.hj_hold_button then return true end
            card.children.hj_hold_button = UIBox {
                definition = {
                    n = G.UIT.ROOT,
                    config = {
                        ref_table = card,
                        minw = 1.1, maxw = 1.3, padding = 0.1,
                        align  = 'cl',
                        colour = { 0.3, 0.5, 0.9, 1 },
                        shadow = true, r = 0.08, minh = 0.94,
                        func   = 'hj_can_hold',
                        button = 'hj_hold_joker',
                        hover  = true,
                    },
                    nodes = {
                        { n = G.UIT.T, config = { text = 'Hold',
                                                   colour = G.C.WHITE, scale = 0.5 } }
                    },
                },
                config = {
                    align  = 'cl',
                    offset = { x = 0.3, y = 0 },
                    major  = card,
                    bond   = 'Weak',
                    parent = card,
                },
            }
            return true
        end,
    }))
end

local orig_create_shop_card_ui = create_shop_card_ui
create_shop_card_ui = function(card, type, area)
    orig_create_shop_card_ui(card, type, area)
    if card.config.center.set == 'Joker' then
        HJ.inject_hold_button(card)
    end
end

local orig_CardArea_emplace = CardArea.emplace
function CardArea.emplace(self, card, ...)
    local ret = orig_CardArea_emplace(self, card, ...)
    if G.pack_cards and self == G.pack_cards
       and card.config and card.config.center
       and card.config.center.set == 'Joker' then
        HJ.inject_hold_button(card)
    end
    return ret
end

-- ─── Held-slot card UI ────────────────────────────────────────────────────────

function HJ.create_held_card_ui(card)
    local s = HJ.SCALE

    G.E_MANAGER:add_event(Event({
        trigger   = 'after',
        delay     = 0.43,
        blocking  = false,
        blockable = false,
        func = function()
            if card.removed then return true end

            card.children.hj_sell_price = UIBox {
                definition = {
                    n = G.UIT.ROOT,
                    config = { minw = 0.6 * s, align = 'tm',
                               colour = darken(G.C.BLACK, 0.2),
                               shadow = true, r = 0.05, padding = 0.03, minh = 0.6 * s },
                    nodes = {{
                        n = G.UIT.R,
                        config = { align = "cm", colour = lighten(G.C.BLACK, 0.1),
                                   r = 0.1, minw = 0.6 * s, minh = 0.3 * s,
                                   emboss = 0.05, padding = 0.02 },
                        nodes = {{ n = G.UIT.O, config = { object = DynaText({
                            string   = {{ prefix = localize('$'),
                                          ref_table = card, ref_value = 'sell_cost' }},
                            colours  = { G.C.MONEY },
                            shadow = true, silent = true,
                            bump   = true, pop_in = 0, scale = 0.35,
                        })}}}
                    }},
                },
                config = { align = 'tm', offset = { x = 0, y = 0.38 * s },
                           major = card, bond = 'Weak', parent = card },
            }

            card.children.hj_add_button = UIBox {
                definition = {
                    n = G.UIT.ROOT,
                    config = {
                        ref_table = card,
                        minw = 0.7, maxw = 0.8, padding = 0.05,
                        align  = 'bm',
                        colour = { 0.2, 0.65, 0.2, 1 },
                        shadow = true, r = 0.08, minh = 0.5,
                        func   = 'hj_can_add',
                        button = 'hj_add_to_jokers',
                        hover  = true,
                    },
                    nodes = {
                        { n = G.UIT.T, config = { text = 'Add',
                                                   colour = G.C.WHITE, scale = 0.35 } }
                    },
                },
                config = { align = 'bm', offset = { x = 0, y = -0.3 * s },
                           major = card, bond = 'Weak', parent = card },
            }

            if not card.ability.eternal then
                card.children.hj_sell_button = UIBox {
                    definition = {
                        n = G.UIT.ROOT,
                        config = {
                            ref_table = card,
                            minw = 0.7, maxw = 0.8, padding = 0.05,
                            align  = 'cl',
                            colour = G.C.RED,
                            shadow = true, r = 0.08, minh = 0.5,
                            func   = 'hj_can_sell',
                            button = 'hj_sell_held',
                            hover  = true,
                        },
                        nodes = {
                            { n = G.UIT.T, config = { text = 'Sell',
                                                       colour = G.C.WHITE, scale = 0.35 } }
                        },
                    },
                    config = { align = 'cl', offset = { x = 0.3 * s, y = 0 },
                               major = card, bond = 'Weak', parent = card },
                }
            end
            return true
        end,
    }))
end

-- ─── Button condition checks ──────────────────────────────────────────────────

G.FUNCS.hj_can_hold = function(e)
    local card = e.config.ref_table
    local slot_free = G.hj_held_area and G.hj_held_area.cards
                      and #G.hj_held_area.cards == 0
                      and not G.GAME.hj_held_data
    local from_pack = G.pack_cards and card and card.area == G.pack_cards
    local can_afford = from_pack or (card and G.GAME.dollars >= card.cost)
    if slot_free and can_afford then
        e.config.button = 'hj_hold_joker'
    else
        e.config.button = nil
    end
end

G.FUNCS.hj_can_add = function(e)
    local card  = e.config.ref_table
    local extra = (card and card.edition and card.edition.negative) and 1 or 0
    if G.jokers and #G.jokers.cards < G.jokers.config.card_limit + extra then
        e.config.button = 'hj_add_to_jokers'
    else
        e.config.button = nil
    end
end

G.FUNCS.hj_can_sell = function(e)
    local card = e.config.ref_table
    if card and not card.ability.eternal then
        e.config.button = 'hj_sell_held'
    else
        e.config.button = nil
    end
end

-- ─── Shared cleanup helpers ───────────────────────────────────────────────────

local function hj_clean_shop_children(card)
    for _, k in ipairs { 'price', 'buy_button', 'buy_and_use_button',
                         'use_button', 'hj_hold_button' } do
        if card.children[k] then
            card.children[k]:remove()
            card.children[k] = nil
        end
    end
    remove_nils(card.children)
end

local function hj_clean_held_children(card)
    for _, k in ipairs { 'hj_sell_price', 'hj_add_button', 'hj_sell_button' } do
        if card.children[k] then
            card.children[k]:remove()
            card.children[k] = nil
        end
    end
    remove_nils(card.children)
end

-- ─── Actions ─────────────────────────────────────────────────────────────────

G.FUNCS.hj_hold_joker = function(e)
    local c1 = e.config.ref_table
    if not (c1 and c1:is(Card)) then return end
    if not G.hj_held_area or not G.hj_held_area.cards
       or #G.hj_held_area.cards > 0 then return end

    local from_pack = G.pack_cards and c1.area == G.pack_cards

    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay   = 0.1,
        func    = function()
            c1.area:remove_card(c1)
            hj_clean_shop_children(c1)

            if not from_pack then
                G.GAME.round_scores.cards_purchased.amt =
                    G.GAME.round_scores.cards_purchased.amt + 1
                G.GAME.current_round.jokers_purchased =
                    (G.GAME.current_round.jokers_purchased or 0) + 1
                inc_career_stat('c_shop_dollars_spent', c1.cost)
                if c1.cost ~= 0 then ease_dollars(-c1.cost) end
            end
            play_sound('card1')

            save_held_data(c1)
            G.hj_held_area:emplace(c1)
            c1.T.w = G.CARD_W * HJ.SCALE
            c1.T.h = G.CARD_H * HJ.SCALE
            HJ.create_held_card_ui(c1)

            if from_pack and G.FUNCS.skip_booster then
                G.E_MANAGER:add_event(Event({
                    trigger = 'after',
                    delay   = 0.2,
                    func    = function()
                        G.FUNCS.skip_booster()
                        return true
                    end
                }))
            end

            return true
        end,
    }))
end

G.FUNCS.hj_add_to_jokers = function(e)
    local c1 = e.config.ref_table
    if not (c1 and c1:is(Card)) then return end
    local extra = (c1.edition and c1.edition.negative) and 1 or 0
    if #G.jokers.cards >= G.jokers.config.card_limit + extra then return end

    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay   = 0.1,
        func    = function()
            hj_clean_held_children(c1)
            G.hj_held_area:remove_card(c1)
            G.GAME.hj_held_data = nil
            c1.T.w = G.CARD_W
            c1.T.h = G.CARD_H
            G.jokers:emplace(c1)

            G.E_MANAGER:add_event(Event({ func = function()
                c1:calculate_joker({ buying_card = true, card = c1 })
                return true
            end }))
            for i = 1, #G.jokers.cards do
                G.jokers.cards[i]:calculate_joker({ buying_card = true, card = c1 })
            end

            if G.GAME.modifiers.inflation then
                G.GAME.inflation = G.GAME.inflation + 1
                G.E_MANAGER:add_event(Event({ func = function()
                    for _, v in pairs(G.I.CARD) do
                        if v.set_cost then v:set_cost() end
                    end
                    return true
                end }))
            end

            play_sound('card1')
            G.CONTROLLER:save_cardarea_focus('jokers')
            G.CONTROLLER:recall_cardarea_focus('jokers')
            return true
        end,
    }))
end

G.FUNCS.hj_sell_held = function(e)
    local c1 = e.config.ref_table
    if not (c1 and c1:is(Card)) then return end
    if c1.ability.eternal then return end

    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay   = 0.1,
        func    = function()
            hj_clean_held_children(c1)
            G.GAME.hj_held_data = nil
            c1.T.w = G.CARD_W
            c1.T.h = G.CARD_H
            c1:sell_card()
            return true
        end,
    }))
end

print('[HeldJoker] Loaded.')
