export type UIController = {
	Player: Player,
	PlayerGui: PlayerGui,
	pages: { [string]: any },
	openPage: (self: UIController, pageName: string, data: any?) -> boolean,
	closePage: (self: UIController, pageName: string) -> boolean,
	isPageOpen: (self: UIController, pageName: string) -> boolean,
}

return {}
