export type MatchState = "Loading" | "Countdown" | "Searching" | "TargetFound" | "Results" | "Returning" | "Ended"
export type QueueState = "Empty" | "Waiting" | "CountingDown" | "Locked" | "Teleporting" | "Resetting"
export type NotificationKind = "Info" | "Success" | "Warning" | "Error" | "Premium"
export type ServerRole = "Combined" | "Lobby" | "Match"

export type Profile = {
	SchemaVersion: number,
	HighestRoomCompleted: number,
	ObjectsFound: number,
	FinderWins: number,
	TotalMessCleared: number,
	BestTimes: { [string]: number },
	TutorialCompleted: boolean,
	Checkpoint: {
		RoomId: number?,
		Percent: number,
		RoomCash: number,
		SearchPowerLevel: number,
		SearchSpeedLevel: number,
		BagLevel: number,
		MoveSpeedLevel: number,
		UpdatedAt: number,
	},
	Settings: {
		Music: boolean,
		SFX: boolean,
		ReduceVFX: boolean,
		CameraShake: boolean,
	},
	Boosts: {
		SearchPowerExpiresAt: number,
		CashExpiresAt: number,
	},
	PurchaseHistory: { [string]: number },
}

return nil
