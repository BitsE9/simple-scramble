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

static ConVar s_ConVar_RequestBuddyAdminFlags;

static int s_RequestBuddyAdminFlags;

static bool g_ClientBuddies[MAXPLAYERS][MAXPLAYERS];

void PluginStartBuddySystem() {
	s_ConVar_RequestBuddyAdminFlags = CreateConVar(
		"ss_request_buddy_admin_flags", "",
		"Users must have these admin flags in order to request buddies."
	);
	s_ConVar_RequestBuddyAdminFlags.AddChangeHook(conVarChanged_RequestBuddyAdminFlags);
	{
		char adminFlags[32];
		s_ConVar_RequestBuddyAdminFlags.GetString(adminFlags, sizeof(adminFlags));
		s_RequestBuddyAdminFlags = ReadFlagString(adminFlags);
	}

	RegConsoleCmd("sm_addbuddy", cmd_AddBuddy, "Add a player to your buddy list. The balance system attempts to pair buddies together.");
}

static void conVarChanged_RequestBuddyAdminFlags(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_RequestBuddyAdminFlags = ReadFlagString(newValue);
}

void InitClientBuddies(int client) {
	for (int i = 1; i <= MaxClients; ++i) {
		g_ClientBuddies[client][i] = false;
		g_ClientBuddies[i][client] = false;
	}
}

static Action cmd_AddBuddy(int client, int args) {
	if (client != 0) {
		if (args >= 1) {
			char targetPattern[MAX_NAME_LENGTH];
			GetCmdArgString(targetPattern, sizeof(targetPattern));

			int target = FindTarget(client, targetPattern, false, false);
			if (target > 0) {
				ClientAddBuddy(client, target);
			}
		} else {
			showAddBuddyMenu(client);
		}
	}
	return Plugin_Handled;
}

static bool canClientRequestBuddies(int client) {
	if (IsFakeClient(client)) {
		return true;
	} else {
		int adminFlags = GetUserFlagBits(client);
		return (adminFlags & s_RequestBuddyAdminFlags) == s_RequestBuddyAdminFlags || (adminFlags & ADMFLAG_ROOT) != 0;
	}
}

static void showAddBuddyMenu(int client) {
	bool canRequest = canClientRequestBuddies(client);
	Menu menu = CreateMenu(addBuddyMenuHandler);
	menu.SetTitle("%t", "AddBuddyMenuTitle");
	char targetName[MAX_NAME_LENGTH + 1];
	char targetUserId[16];
	for (int i = 1; i <= MaxClients; ++i) {
		if (client != i && IsClientConnected(i)) {
			if (canRequest || g_ClientBuddies[i][client]) {
				GetClientName(i, targetName, sizeof(targetName));
				Format(targetUserId, sizeof(targetUserId), "%d", GetClientUserId(i));
				int itemStyle = g_ClientBuddies[client][i] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT;
				menu.AddItem(targetUserId, targetName, itemStyle);
			}
		}
	}
	menu.Display(client, MENU_TIME_FOREVER);
}

void addBuddyMenuHandler(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select:
		{
			char targetUserId[16];
			menu.GetItem(param2, targetUserId, sizeof(targetUserId));
			int target = GetClientOfUserId(StringToInt(targetUserId));
			if (target != 0) {
				ReplySource oldReplySource = SetCmdReplySource(SM_REPLY_TO_CHAT);
				ClientAddBuddy(param1, target);
				SetCmdReplySource(oldReplySource);
			}
		}
		case MenuAction_End:
			delete menu;
	}
}

enum BuddyResult {
	BuddyResult_RequestNoPerm,
	BuddyResult_Request,
	BuddyResult_AlreadyRequested,
	BuddyResult_Accept,
	BuddyResult_AlreadyBuddy,
}

void ClientAddBuddy(int client, int target) {
	if (client != target) {
		BuddyResult result;
		if (!g_ClientBuddies[client][target]) {
			if (!g_ClientBuddies[target][client]) {
				if (canClientRequestBuddies(client)) {
					result = BuddyResult_Request;
				} else {
					result = BuddyResult_RequestNoPerm;
				}
			} else {
				result = BuddyResult_Accept;
			}
		} else {
			if (g_ClientBuddies[target][client]) {
				result = BuddyResult_AlreadyBuddy;
			} else {
				result = BuddyResult_AlreadyRequested;
			}
		}

		int messageColorCode;
		switch (result) {
			case BuddyResult_RequestNoPerm:
				messageColorCode = g_MessageFailureColorCode;
			case BuddyResult_Request:
				messageColorCode = g_MessageNotificationColorCode;
			case BuddyResult_AlreadyRequested:
				messageColorCode = g_MessageFailureColorCode;
			case BuddyResult_Accept:
				messageColorCode = g_MessageSuccessColorCode;
			case BuddyResult_AlreadyBuddy:
				messageColorCode = g_MessageSuccessColorCode;
		}

		char clientName[MAX_NAME_LENGTH_COLORED + 1];
		char targetName[MAX_NAME_LENGTH_COLORED + 1];
		GetClientNameTeamColored(client, messageColorCode, clientName, sizeof(clientName));
		GetClientNameTeamColored(target, messageColorCode, targetName, sizeof(targetName));

		switch (result) {
			case BuddyResult_RequestNoPerm: {
				SS_ReplyToCommand(client, "\x07%06X%t", messageColorCode, "RequestBuddyNoPerm");
			}
			case BuddyResult_Request: {
				g_ClientBuddies[client][target] = true;
				SS_ReplyToCommand(client, "\x07%06X%t", messageColorCode, "RequestBuddy", targetName);
				SS_PrintToChat(target, 0, "\x07%06X%t", messageColorCode, "RequestedBuddy", clientName);

				// Bots will immediately accept requests.
				if (IsFakeClient(target)) {
					ClientAddBuddy(target, client);
				}
			}
			case BuddyResult_AlreadyRequested: {
				SS_ReplyToCommand(client, "\x07%06X%t", messageColorCode, "AlreadyRequestedBuddy", targetName);
			}
			case BuddyResult_Accept: {
				g_ClientBuddies[client][target] = true;
				SS_ReplyToCommand(client, "\x07%06X%t", messageColorCode, "AcceptBuddy", targetName);
				SS_PrintToChat(target, 0, "\x07%06X%t", messageColorCode, "AcceptedBuddy", clientName);
			}
			case BuddyResult_AlreadyBuddy: {
				SS_ReplyToCommand(client, "\x07%06X%t", messageColorCode, "AlreadyBuddy", targetName);
			}
		}

	} else {
		SS_ReplyToCommand(client, "\x07%06X%t", g_MessageFailureColorCode, "SelfBuddyError");
	}
}

bool AreClientsBuddies(int client1, int client2) {
	return g_ClientBuddies[client1][client2] && g_ClientBuddies[client2][client1];
}