--!AUTOGEN-BEGIN-ARGS (do not edit, regenerated when you save the command)
export type ArgumentResult = {
	HostName: string,
	Preview: boolean,
}
--!AUTOGEN-END-ARGS

export type Argument = {
	Type: "string" | "number" | "paragraph" | "output" | "boolean" | "switch" | "button" | "label" | "dropdown" | "instance" | "color" | "slider" | "propertyPicker" | "attributePicker" | "colorPicker",
	Default: any,
	Description: string?,
	LayoutOrder: number?,
	ClearTextOnFocus: boolean?,
	PlaceholderText: string?,
	Min: number?,
	Max: number?,
	Step: number?,
	Options: { any }?,
	AllowCustom: boolean?,
	IsEditable: boolean?,
	ShowFullPath: boolean?,
	Timestamp: boolean?,
	Property: string?,
	Attribute: string?,
	Run: (props: Props, value: any) -> ()?,
}

export type ArgumentType = {
	[string]: Argument?
}

export type Configuration = {
    properties: { [string]: any },
    Get: (self: Configuration, key: string, default: any?) -> any,
    Set: (self: Configuration, key: string, value: any) -> (),
}

export type NotificationParams = {
	Text: string,
	Timeout: number?,
	Button1Text: string?,
	Button1TextColor: Color3?,
	Button1Color: Color3?,
	Button1Callback: (() -> ())?,
	Button2Text: string?,
	Button2TextColor: Color3?,
	Button2Color: Color3?,
	Button2Callback: (() -> ())?,
}

export type OutputHandle = {
	Name: string?,
	print: (self: OutputHandle, text: any) -> OutputHandle,
	warn: (self: OutputHandle, text: any) -> OutputHandle,
	error: (self: OutputHandle, text: any) -> OutputHandle,
	clear: (self: OutputHandle) -> OutputHandle,
}
export type Props = {
	Arguments: any,
	Selected: {any},
	FirstSelected: any?,
	Plugin: Plugin,
	any: any,
	Configuration: Configuration,
	RunCommand: (self: any, command: string, arguments: {}?) -> (),
	ViewCommand: (self: any, command: string) -> (),
	SetLabelText: (self: any, labelName: string, text: string) -> (),
	GetLabelText: (self: any, labelName: string) -> string?,
	AppendOutput: (self: any, outputName: string, text: string) -> (),
	ClearOutput: (self: any, outputName: string) -> (),
	Output: (self: any, outputName: string?) -> OutputHandle,
	SetSelection: (self: any, selection: {Instance}) -> (),
	FocusView: (self: any, objects: any, extraOffset: number?) -> (),
	SendNotification: (self: any, params: NotificationParams) -> (),
}

export type ScriptModule = {
	AutoRecordChanges: boolean?,
	Debug: boolean?,
	DisableExecuteButton: boolean?,
	Description: string?,
	Tags: { string }?,
	Arguments: ArgumentType,
	Run: (props: Props, arguments: ArgumentResult) -> (),
	Validate: ((props: Props) -> (boolean, string?))?,
	OnExecuted: ((props: Props, arguments: ArgumentResult, result: any) -> ())?,
	OnError: ((props: Props, arguments: ArgumentResult, err: string) -> ())?,
	OnSelected: ((props: Props) -> ())?,
	OnDeselected: ((props: Props) -> ())?,
}

return nil
