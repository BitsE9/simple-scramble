/*
 * simple-scramble
 * Copyright (C) 2026  BitsE9
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/**
 * @return true if the game is in the waiting for players phase.
 */
bool IsInWaitingForPlayers() {
	return GameRules_GetProp("m_bInWaitingForPlayers") ? true : false;
}

/**
 * @return true if the game is in the setup phase.
 */
bool IsInSetup() {
	return GameRules_GetProp("m_bInSetup") ? true : false;
}

/**
 * @return true if the game is in the pre-round phase.
 */
bool IsInPreRound() {
	return GameRules_GetRoundState() == RoundState_Preround;
}

/**
 * @return true if the game is in a post round phase.
 */
bool IsInPostRound() {
	RoundState roundState = GameRules_GetRoundState();
	return roundState == RoundState_TeamWin || roundState == RoundState_Bonus || roundState == RoundState_BetweenRounds;
}

/**
 * @return true if the teams were switched this round.
 */
bool SwitchedTeamsThisRound() {
	return GameRules_GetProp("m_bSwitchedTeamsThisRound") ? true : false;
}

/**
 * Retrieves the active round timer.
 *
 * @return    Entity index of the round timer or -1 if none exists.
 */
int GetActiveRoundTimer() {
	int objectiveResource = FindEntityByClassname(-1, "tf_objective_resource");
	if (IsValidEntity(objectiveResource)) {
		return GetEntProp(objectiveResource, Prop_Send, "m_iTimerToShowInHUD");
	} else {
		return -1;
	}
}

/**
 * Resets the setup timer to the initial duration.
 *
 * @noreturn
 */
void ResetSetupTimer() {
	int roundTimer = GetActiveRoundTimer();
	if (IsValidEntity(roundTimer)) {
		int setupTime = GetEntProp(roundTimer, Prop_Send, "m_nSetupTimeLength");
		SetVariantInt(setupTime);
		AcceptEntityInput(roundTimer, "SetSetupTime");
	}
}

/**
 * Removes all of a client's owned entities.
 *
 * @param explodeBuildings    Whether or not to explode the client's buildings.
 * @noreturn
 */
void RemoveClientOwnedEntities(int client, bool explodeBuildings = false) {
	SDKCall(g_SDKCall_RemoveAllOwnedEntitiesFromWorld, client, !explodeBuildings);
}

static char s_PickupClassnames[][] = {
	"item_ammopack_small",
	"item_ammopack_medium",
	"item_ammopack_full",
	"item_healthkit_small",
	"item_healthkit_medium",
	"item_healthkit_full",
};

/**
 * Respawns all item pickups.
 *
 * @noreturn
 */
void RespawnPickups() {
	for (int i = 0; i < 6; ++i) {
		int entity = -1;
		while ((entity = FindEntityByClassname(entity, s_PickupClassnames[i])) != -1) {
			AcceptEntityInput(entity, "RespawnNow");
		}
	}
}

/**
 * @return the mask of playable teams.
 */
int GetPlayTeamActiveMask() {
	return GameRules_GetProp("m_iTeamsActive");
}

/**
 * Check if the given team is active.
 *
 * @param team    Index of the team to check.
 * @return        true if the team is active.
 */
bool IsPlayTeamActive(int team) {
	return GetPlayTeamActiveMask() & (1 << (team - TEAM_FIRST_PLAY)) != 0;
}

/**
 * @return the number of playable teams.
 */
int GetPlayTeamCount() {
	int mask = GetPlayTeamActiveMask();
	int count = 0;
	for (int i = 0; i < TEAM_MAX_PLAY; ++i) {
		if ((mask & (1 << i)) != 0) {
			++count;
		}
	}
	return count;
}

/**
 * Check if the given team is escorting a VIP.
 *
 * @param team    Index of the team to check.
 * @return        true if the team is escorting a VIP.
 */
bool IsTeamEscorting(int team) {
	return GetEntProp(GetTeamEntity(team), Prop_Send, "m_bEscortingVIP") ? true : false;
}

/**
 * Gets the VIP of the given team.
 *
 * @param team    Index of the team to get the VIP of.
 * @return        Client index of the team's VIP or 0 if none.
 */
/*int GetTeamVIP(int team) {
	return GetEntProp(GetTeamEntity(team), Prop_Send, "m_iVIP");
}*/

/**
 * Get a client's medigun.
 *
 * @param client    Client to get the medigun of.
 * @return          Entity index of the client's medigun.
 */
int GetClientMedigun(int client) {
	int secondary = GetPlayerWeaponSlot(client, 1);
	char secondaryClassname[32];
	if (IsValidEntity(secondary)) {
		GetEntityClassname(secondary, secondaryClassname, sizeof(secondaryClassname));
		if (StrEqual(secondaryClassname, "tf_weapon_medigun", false)) {
			return secondary;
		}
	}

	return -1;
}

/**
 * Changes a client's team and respawns them.
 *
 * @param client    Client to change the team of.
 * @param team      Team to put the client on.
 * @noreturn
 */
void ChangeClientTeamRespawn(int client, int team) {
	if (IsPlayerAlive(client)) {
		// Hack to prevent the player from suiciding when they change teams.
		SetEntProp(client, Prop_Send, "m_lifeState", 2);
	}
	ChangeClientTeam(client, team);
	SS_RespawnPlayer(client);
}

/**
 * Retrieves the short name of a team.
 *
 * @param team       Team to get the name of.
 * @param dest       Destination buffer.
 * @param destLen    Length of the destination buffer.
 * @noreturn
 */
void GetTeamShortName(int team, char[] dest, int destLen) {
	switch(team) {
		case TEAM_RED:
			strcopy(dest, destLen, "RED");
		case TEAM_BLUE:
			strcopy(dest, destLen, "BLU");
		case TEAM_GREEN:
			strcopy(dest, destLen, "GRN");
		case TEAM_YELLOW:
			strcopy(dest, destLen, "YLW");
		default:
			strcopy(dest, destLen, "<!>");
	}
}

/**
 * Retrieves hex code for a team's color.
 *
 * @param team       Team to get the name of.
 * @return           Hex color code for the team.
 */
int GetTeamColorCode(int team) {
	switch(team) {
		case TEAM_RED:
			return 0xff3d32;
		case TEAM_BLUE:
			return 0x9acdff;
		case TEAM_GREEN:
			return 0x9aff9a;
		case TEAM_YELLOW:
			return 0xffb400;
		default:
			return 0xcdcdcd;
	}
}

/**
 * Returns the client's name with a color applied.
 *
 * @param client    Client index.
 * @param name      Buffer to store the client's name.
 * @param maxlen    Maximum length of string buffer (includes NULL terminator).
 * @param clr       Color code for the client's name. 
 * @param endClr    Color code following the client's name. 
 * @noreturn
 */
void GetClientNameColored(int client, int clr, int endClr, char[] name, int maxlen) {
	GetClientName(client, name, maxlen);
	Format(name, maxlen, "\x07%06X%s\x07%06X", clr, name, endClr);
}

/**
 * Returns the client's with their team color applied.
 *
 * @param client    Client index.
 * @param name      Buffer to store the client's name.
 * @param maxlen    Maximum length of string buffer (includes NULL terminator).
 * @param endClr    Color code following the client's name. 
 * @noreturn
 */
void GetClientNameTeamColored(int client, int endClr, char[] name, int maxlen) {
	GetClientNameColored(client, GetTeamColorCode(GetClientTeam(client)), endClr, name, maxlen);
}

/**
 * Converts a hex string to an integer.
 *
 * @param buf       Buffer to extract the code from.
 * @param bufLen    The length of the buffer.
 */
int HexToInt(const char[] buf, int bufLen = INT_MAX) {
	int code = 0;

	int i = 0;
	char c;
	while (i < bufLen) {
		c = buf[i++];
		if (c == '\0') {
			break;
		}

		if (c >= '0' && c <= '9') {
			c = c - '0';
		} else if (c >= 'a' && c <= 'f') {
			c = (c - 'a') + 10;
		} else if (c >= 'A' && c <= 'F') {
			c = (c - 'A') + 10;
		}

		code = (code << 4) | (c & 0xF);
	}

	return code;
}

/**
 * Removes chat color code characters from a string.
 *
 * @param dest       Destination buffer.
 * @param destLen    Length of the destination buffer.
 * @param src        Source buffer.
 * @param srcLen     Length of the source buffer.
 * @noreturn
 */
void RemoveColorCodes(char[] dest, int destLen, const char[] src, int srcLen = INT_MAX) {
	if (destLen > 0) {
		bool finished = false;
		int readIdx = 0;
		int writeIdx = 0;
		int skipCount = 0;
		
		while (readIdx < srcLen && writeIdx < destLen - 1) {
			if (skipCount > 0) {
				--skipCount;
				++readIdx;
				continue;
			}

			char c = src[readIdx++];
			switch(c) {
				case '\0': finished = true;
				case '\x01': skipCount = 1;
				case '\x02': skipCount = 1;
				case '\x03': skipCount = 1;
				case '\x04': skipCount = 1;
				case '\x05': skipCount = 1;
				case '\x06': skipCount = 1;
				case '\x07': skipCount = 7;
				case '\x08': skipCount = 9;
			}

			if (finished) {
				break;
			} else if (skipCount > 0) {
				--skipCount;
				continue;
			}

			dest[writeIdx++] = c;
		}
		dest[writeIdx] = '\0';
	}
}

/**
 * Formats a float to a string with the decimal places rounded.
 *
 * @param dest        Destination buffer.
 * @param destLen     Length of the destination buffer.
 * @param value       Float to round.
 * @param decimals    Number of decimal places to keep.
 * @return            False if the destination buffer cannot hold the value.
 */
bool FormatRoundedFloat(char[] dest, int destLen, float value, int decimals) {
	if (destLen > 0 && decimals < 16) {
		float fract = FloatFraction(value);
		int fractIntMult = RoundFloat(Pow(10.0, float(decimals)));
		fract *= fractIntMult;

		int wholeInt = RoundToFloor(value);
		int fractInt = RoundToNearest(fract);
		if (fractInt > fract && fractInt == fractIntMult) {
			fractInt = 0;
			++wholeInt;
		}

		char wholeStr[16];
		int wholeLen = IntToString(wholeInt, wholeStr, sizeof(wholeStr));

		char decimalStr[16];
		int fractLen = IntToString(fractInt, decimalStr, sizeof(decimalStr));

		int trailingZeros = decimals - fractLen;

		if (destLen >= wholeLen + fractLen + trailingZeros + 1) {
			char trailingStr[16];
			{
				int i = 0;
				for (i = 0; i < trailingZeros; ++i) {
					trailingStr[i++] = '0';
				}
				trailingStr[i] = '\0';
			}

			Format(dest, destLen, "%s.%s%s", wholeStr, decimalStr, trailingStr);
			return true;
		} else {
			return false;
		}
	} else {
		return false;
	}
}

/**
 * Prints a message to a specific client in the chat area.
 *
 * @param client        Client index.
 * @param author        Client index of the message author or 0 for server.
 * @param format        Formatting rules.
 * @param ...           Variable number of format parameters.
 * @error               If the client is not connected an error will be thrown.
 */
void SS_PrintToChat(int client, int author, const char[] format, any ...) {
	if (client != 0) {
		if (!IsClientInGame(client)) {
			ThrowError("Client %d is not in game", client);
		}
		char buffer[254];
		SetGlobalTransTarget(client);
		VFormat(buffer, sizeof(buffer), format, 4);

		Handle msg = StartMessageOne("SayText2", client, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS);
		BfWriteByte(msg, author);
		BfWriteByte(msg, true); // chat - this affects whether or not the client filters this as chat
		                        //        but also determines if the message is posted to the console
		BfWriteString(msg, buffer);
		EndMessage();
	}
}

/**
 * Prints a message to all clients in the chat area.
 *
 * @param author        Client index of the message author or 0 for server.
 * @param format        Formatting rules.
 * @param ...           Variable number of format parameters.
 */
void SS_PrintToChatAll(int author, const char[] format, any ...) {
	char buffer[254];
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			SetGlobalTransTarget(i);
			VFormat(buffer, sizeof(buffer), format, 3);
			SS_PrintToChat(i, author, "%s", buffer);
		}
	}
}

/**
 * Replies to a message in a command.
 *
 * @param client    Client index, or 0 for server.
 * @param format    Formatting rules.
 * @param ...       Variable number of format parameters.
 * @error           If the client is not connected an error will be thrown.
 * @noreturn
 */
void SS_ReplyToCommand(int client, const char[] format, any ...)
{
	char buffer[254];
	SetGlobalTransTarget(client);
	VFormat(buffer, sizeof(buffer), format, 3);

	if (client == 0) {
		RemoveColorCodes(buffer, sizeof(buffer), buffer, sizeof(buffer));
		PrintToServer("%s", buffer);
	} else if (GetCmdReplySource() == SM_REPLY_TO_CHAT) {
		SS_PrintToChat(client, 0, "%s", buffer);
	} else {
		RemoveColorCodes(buffer, sizeof(buffer), buffer, sizeof(buffer));
		PrintToConsole(client, "%s", buffer);
	}
}

/**
 * Respawns a player.
 *
 * @noreturn
 */
void SS_RespawnPlayer(int client) {
	SDKCall(g_SDKCall_ForceRespawn, client);
}

int SS_GetPlayerClass(int client)
{
	return GetEntProp(client, Prop_Send, "m_iClass");
}

void SS_SetPlayerClass(int client, int classType)
{
	SetEntProp(client, Prop_Send, "m_iClass", classType);
	SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", classType);
}
