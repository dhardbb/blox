--!strict
-- The contract every screen module follows. A screen module returns
-- { mount = function(parent: Frame, ctx: Ctx): Screen }. The router mounts the
-- screen that fits the current state, calls update() on every Store change and
-- tick() four times a second (for countdowns), and destroy() when it leaves.
--
-- Screens read ONLY ctx.store.get() (the server's payload for this player, i.e.
-- their own View) and send ONLY through ctx.net. They never require server code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)

export type State = {
	payload: any?, -- Session.StatePayload
	lobby: any?, -- Remotes.LobbyStatus
	messages: { string },
	resultSeen: boolean,
	prePick: any?,
}

export type Net = {
	send: (op: string, fields: { [string]: any }?) -> (),
	submit: (input: any) -> (),
	bank: () -> (),
	skip: () -> (),
	reasonText: (reason: string?) -> string,
}

export type Store = {
	get: () -> State,
	dismissResult: () -> (),
	setPrePick: (pick: any) -> (),
	say: (message: string) -> (),
}

export type Ctx = {
	config: ConfigModule.Config,
	store: Store,
	net: Net,
	now: () -> number, -- server time (workspace:GetServerTimeNow())
	portrait: () -> boolean, -- true when the screen is taller than wide (phones)
}

export type Screen = {
	update: (state: State) -> (),
	tick: ((now: number) -> ())?,
	destroy: () -> (),
}

return {}
