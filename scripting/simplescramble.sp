/*
 * smart-scramble
 * Copyright (C) 2024  Jaws
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

#include <sourcemod>
#include <sdktools>
#include <profiler>

#include <tf2c>
#include <hlxce-sm-api>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name = "Smart Scramble",
	author = "Jaws, sbebular",
	description = "Very simple scramble functionality for TF2 Classic, with extra points/time scoring mode",
	version = "1.2",
	url = "https://github.com/Jaws576/smart-scramble"
};

#include "smartscramble/defs.sp"

enum ScrambleMethod {
	ScrambleMethod_Shuffle = 0,
	ScrambleMethod_TopToWeakestTeam = 1,
}

enum AdminScrambleOpts {
	AdminScrambleOpt_None    = 0,
	AdminScrambleOpt_Restart = (1 << 0),
	AdminScrambleOpt_Respawn = (1 << 1),
	AdminScrambleOpt_Retain  = (1 << 2),
}

enum RespawnMode {
	RespawnMode_Dont,
	RespawnMode_Normal,
	RespawnMode_Retain,
	RespawnMode_Reset,
}

enum DatabaseKind {
	DatabaseKind_None,
	DatabaseKind_HLXCE,
}

Handle g_SDKCall_RemoveAllOwnedEntitiesFromWorld;
DynamicHook g_Hook_GameRules_ShouldScramble;

static ConVar s_ConVar_ScrambleVoteEnabled;
static ConVar s_ConVar_TeamsUnbalanceLimit;
static ConVar s_ConVar_ScrambleMethod;
static ConVar s_ConVar_SpecTimeout;
static ConVar s_ConVar_ScrambleVoteRatio;
static ConVar s_ConVar_ScrambleVoteRestartSetup;
static ConVar s_ConVar_ScrambleVoteCooldown;
static ConVar s_ConVar_TeamStatsAdminFlags;

static ConVar s_ConVar_ScrambleOnLoadRatio;

static ConVar s_ConVar_MessageNotificationColorCode;
static ConVar s_ConVar_MessageInformationColorCode;
static ConVar s_ConVar_MessageSuccessColorCode;
static ConVar s_ConVar_MessageFailureColorCode;

bool g_ScrambleVoteEnabled;
int g_TeamsUnbalanceLimit;
ScrambleMethod g_ScrambleMethod;
float g_SpecTimeout;
float g_ScrambleVoteRatio;
float g_ScrambleOnLoadRatio;
bool g_ScrambleVoteRestartSetup;
float g_ScrambleVoteCooldown;
static int s_TeamStatsAdminFlags;

int g_MessageNotificationColorCode;
int g_MessageInformationColorCode;
int g_MessageSuccessColorCode;
int g_MessageFailureColorCode;

float g_ClientLastTime[MAXPLAYERS] = {0.0, ...}; //the GAME TIME (seconds since map start) at which the client last had their time updated
float g_ClientPlayTime[MAXPLAYERS] = {0.0, ...}; //the time (in seconds) for which a player has been playing and their score updated
int g_ClientLastScore[MAXPLAYERS] = {0, ...}; //the client's score the last time it was updated
int g_ClientPlayScore[MAXPLAYERS] = {0, ...}; //the total score for a players while they have been tracked
bool g_ClientIsTracking[MAXPLAYERS] = {false, ...};
bool g_ClientScrambleVote[MAXPLAYERS] = {false, ...};

int g_TeamVips[4] = {0, ...};
static StringMap g_LastMapUserIdScores;

int g_HumanClients = 0;
int g_ScrambleVotes = 0;
float g_ScrambleVoteScrambleTime = 0.0;
bool g_RoundScrambleQueued = false;
bool g_ScrambleVotePassed = false;
bool g_SuppressTeamSwitchMessage = false;
bool g_MapStartScramble = false;

bool g_HLCEApiAvailable = false;

#include "smartscramble/debug.sp"
#include "smartscramble/utils.sp"
#include "smartscramble/scoring.sp"
#include "smartscramble/buddies.sp"
#include "smartscramble/autoscramble.sp"
#include "smartscramble/team_builder.sp"

public void OnPluginStart() {
	g_LastMapUserIdScores = new StringMap();
	PrintToServer("pootis");
	LoadTranslations("common.phrases");
	LoadTranslations("smartscramble.phrases");

	GameData gameconf = LoadGameConfigFile("smartscramble");
	if (!gameconf) {
		SetFailState("GameData \"smartscramble.txt\" does not exist.");
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gameconf, SDKConf_Signature, "CTFPlayer::RemoveAllOwnedEntitiesFromWorld");
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	g_SDKCall_RemoveAllOwnedEntitiesFromWorld = EndPrepSDKCall();
	if (g_SDKCall_RemoveAllOwnedEntitiesFromWorld == null) {
		SetFailState("Failed to create SDKCall for \"CTeamplayRoundBasedRules::g_SDKCall_RemoveAllOwnedEntitiesFromWorld\".");
	}

	g_Hook_GameRules_ShouldScramble = DynamicHook.FromConf(gameconf, "CTeamplayRules::ShouldScrambleTeams");
	if (g_Hook_GameRules_ShouldScramble == null) {
		SetFailState("Failed to create hook for \"CTeamplayRules::ShouldScrambleTeams\".");
	}

	delete gameconf;

	PluginStartDebugSystem();
	PluginStartScoringSystem();
	PluginStartBuddySystem();
	PluginStartAutoScrambleSystem();

	// ConVars
	s_ConVar_ScrambleVoteEnabled = FindConVar("sv_vote_issue_scramble_teams_allowed");
	s_ConVar_ScrambleVoteEnabled.AddChangeHook(conVarChanged_ScrambleVoteEnabled);
	g_ScrambleVoteEnabled = s_ConVar_ScrambleVoteEnabled.BoolValue;

	s_ConVar_TeamsUnbalanceLimit = FindConVar("mp_teams_unbalance_limit");
	s_ConVar_TeamsUnbalanceLimit.AddChangeHook(conVarChanged_TeamsUnbalanceLimit);
	g_TeamsUnbalanceLimit = s_ConVar_TeamsUnbalanceLimit.IntValue;

	s_ConVar_ScrambleMethod = CreateConVar(
		"ss_scramble_method", "1",
		"The method used to assign teams to players during a scramble.\n\t0 - Shuffle\n\t1 - Top to Weakest Team",
		_,
		true, 0.0,
		true, 1.0
	);
	s_ConVar_ScrambleMethod.AddChangeHook(conVarChanged_ScrambleMethod);
	g_ScrambleMethod = view_as<ScrambleMethod>(s_ConVar_ScrambleMethod.IntValue);

	s_ConVar_SpecTimeout = CreateConVar(
		"ss_scramble_spec_timeout", "30",
		"Players who have been spectating for longer than this many seconds will not participate in scrambles. Use a negative value to have spectators always participate.",
		_,
		true, -1.0
	);
	s_ConVar_SpecTimeout.AddChangeHook(conVarChanged_SpecTimeout);
	g_SpecTimeout = s_ConVar_SpecTimeout.FloatValue;

	s_ConVar_ScrambleVoteRatio = CreateConVar(
		"ss_scramble_vote_ratio", "0.6",
		"The ratio of human players that must vote to scramble the teams for the vote to pass.",
		_,
		true, 0.0,
		true, 1.0
	);
	s_ConVar_ScrambleVoteRatio.AddChangeHook(conVarChanged_ScrambleVoteRatio);
	g_ScrambleVoteRatio = s_ConVar_ScrambleVoteRatio.FloatValue;

	s_ConVar_ScrambleOnLoadRatio = CreateConVar(
		"ss_map_start_scramble_ratio", "1.5",
		"How many times above average (0.5) should a team's score ratio (sum team score / sum total score) be to scramble at the start of the map.\nThis is checked at the end of waiting for players using data from last map.",
		_,
		true, 1.0
	);
	s_ConVar_ScrambleOnLoadRatio.AddChangeHook(conVarChanged_ScrambleOnLoadRatio);
	g_ScrambleOnLoadRatio = s_ConVar_ScrambleOnLoadRatio.FloatValue;

	s_ConVar_ScrambleVoteRestartSetup = CreateConVar(
		"ss_scramble_vote_restart_setup", "1",
		"Scramble votes that pass during setup will reset the setup timer if set to 1.",
		_,
		true, 0.0,
		true, 1.0
	);
	s_ConVar_ScrambleVoteRestartSetup.AddChangeHook(conVarChanged_ScrambleVoteRestartSetup);
	g_ScrambleVoteRestartSetup = s_ConVar_ScrambleVoteRestartSetup.BoolValue;

	s_ConVar_ScrambleVoteCooldown = CreateConVar(
		"ss_scramble_vote_cooldown", "120",
		"This many seconds must pass following a scramble caused by a scramble vote before another scramble vote may be started.",
		_,
		true, 0.0
	);
	s_ConVar_ScrambleVoteCooldown.AddChangeHook(conVarChanged_ScrambleVoteCooldown);
	g_ScrambleVoteCooldown = s_ConVar_ScrambleVoteCooldown.FloatValue;

	s_ConVar_TeamStatsAdminFlags = CreateConVar(
		"ss_team_stats_admin_flags", "",
		"Users must have these admin flags in order to see team stats."
	);
	s_ConVar_TeamStatsAdminFlags.AddChangeHook(conVarChanged_TeamStatsAdminFlags);
	{
		char adminFlags[32];
		s_ConVar_TeamStatsAdminFlags.GetString(adminFlags, sizeof(adminFlags));
		s_TeamStatsAdminFlags = ReadFlagString(adminFlags);
	}

	s_ConVar_MessageNotificationColorCode = CreateConVar(
		"ss_message_notification_color_code", "fff600",
		"Hex color code for notification messages."
	);
	s_ConVar_MessageNotificationColorCode.AddChangeHook(conVarChanged_MessageNotificationColorCode);
	{
		char buf[16];
		s_ConVar_MessageNotificationColorCode.GetString(buf, sizeof(buf));
		g_MessageNotificationColorCode = HexToInt(buf, sizeof(buf));
	}

	s_ConVar_MessageInformationColorCode = CreateConVar(
		"ss_message_information_color_code", "fbeccb",
		"Hex color code for information messages."
	);
	s_ConVar_MessageInformationColorCode.AddChangeHook(conVarChanged_MessageInformationColorCode);
	{
		char buf[16];
		s_ConVar_MessageInformationColorCode.GetString(buf, sizeof(buf));
		g_MessageInformationColorCode = HexToInt(buf, sizeof(buf));
	}

	s_ConVar_MessageSuccessColorCode = CreateConVar(
		"ss_message_success_color_code", "72ff00",
		"Hex color code for success messages."
	);
	s_ConVar_MessageSuccessColorCode.AddChangeHook(conVarChanged_MessageSuccessColorCode);
	{
		char buf[16];
		s_ConVar_MessageSuccessColorCode.GetString(buf, sizeof(buf));
		g_MessageSuccessColorCode = HexToInt(buf, sizeof(buf));
	}

	s_ConVar_MessageFailureColorCode = CreateConVar(
		"ss_message_failure_color_code", "f40000",
		"Hex color code for failure messages."
	);
	s_ConVar_MessageFailureColorCode.AddChangeHook(conVarChanged_MessageFailureColorCode);
	{
		char buf[16];
		s_ConVar_MessageFailureColorCode.GetString(buf, sizeof(buf));
		g_MessageFailureColorCode = HexToInt(buf, sizeof(buf));
	}

	AutoExecConfig(true, "smartscramble");

	// Commands
	AddCommandListener(cmd_CallVote, "callvote");
	AddCommandListener(cmd_MpScrambleTeams, "mp_scrambleteams");
	RegAdminCmd("sm_scramble", cmd_Scramble,  ADMFLAG_GENERIC | ADMFLAG_KICK, "Performs a scramble. sm_scramble <optional:restart|respawn|retain>");
	RegAdminCmd("sm_scrambleround", cmd_ScrambleRound, ADMFLAG_GENERIC | ADMFLAG_KICK, "Queues a scramble at the end of the round.");
	RegConsoleCmd("sm_teamstats", cmd_TeamStats, "Prints team stats information.");
	RegConsoleCmd("sm_votescramble", cmd_VoteScramble, "Vote to scramble the teams.");


	// Events
	HookEvent("player_team", event_PlayerTeam_Pre, EventHookMode_Pre);
	HookEvent("player_death", event_PlayerDeath_Post, EventHookMode_Post);
	HookEvent("teamplay_round_start", event_RoundStart_Post, EventHookMode_Post);
	HookEvent("teamplay_round_win", event_RoundWin_Post, EventHookMode_Post);
	HookEvent("vip_assigned", event_VipAssigned_Post, EventHookMode_Post);


	for (int i = 1; i <= MaxClients; ++i) {
		if (IsClientConnected(i)) {
			if (!IsFakeClient(i)) {
				++g_HumanClients;
			}

			InitConnectedClient(i);
		}
		if (IsClientInGame(i)) {
			InitInGameClient(i);
		}
	}
}

public void OnMapStart() {
	if (g_Hook_GameRules_ShouldScramble.HookGamerules(Hook_Pre, hook_GameRules_ShouldScramble) == INVALID_HOOK_ID) {
		LogError("Failed to hook gamerules using \"g_Hook_GameRules_ShouldScramble\"");
	}

	PrecacheScriptSound("Announcer.AM_TeamScrambleRandom");

	AutoScrambleGameStart();
	AutoScrambleReset();
	g_RoundScrambleQueued = false;
	g_ScrambleVoteScrambleTime = 0.0;
	g_ScrambleVotePassed = false;
	g_MapStartScramble = true;
}

static void conVarChanged_ScrambleVoteEnabled(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_ScrambleVoteEnabled = StringToInt(newValue) ? true : false;
}

static void conVarChanged_TeamsUnbalanceLimit(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_TeamsUnbalanceLimit = StringToInt(newValue);
}

static void conVarChanged_ScrambleMethod(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_ScrambleMethod = view_as<ScrambleMethod>(StringToInt(newValue));
}

static void conVarChanged_SpecTimeout(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_SpecTimeout = StringToFloat(newValue);
}

static void conVarChanged_ScrambleVoteRatio(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_ScrambleVoteRatio = StringToFloat(newValue);
}

static void conVarChanged_ScrambleOnLoadRatio(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_ScrambleOnLoadRatio = StringToFloat(newValue);
}

static void conVarChanged_ScrambleVoteRestartSetup(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_ScrambleVoteRestartSetup = StringToInt(newValue) ? true : false;
}

static void conVarChanged_ScrambleVoteCooldown(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_ScrambleVoteCooldown = StringToFloat(newValue);
}

static void conVarChanged_TeamStatsAdminFlags(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_TeamStatsAdminFlags = ReadFlagString(newValue);
}

static void conVarChanged_MessageNotificationColorCode(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_MessageNotificationColorCode = HexToInt(newValue);
}

static void conVarChanged_MessageInformationColorCode(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_MessageInformationColorCode = HexToInt(newValue);
}

static void conVarChanged_MessageSuccessColorCode(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_MessageSuccessColorCode = HexToInt(newValue);
}

static void conVarChanged_MessageFailureColorCode(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_MessageFailureColorCode = HexToInt(newValue);
}

static Action cmd_CallVote(int client, const char[] command, int argc) {
	if (argc >= 1) {
		char voteType[16];
		GetCmdArg(1, voteType, sizeof(voteType));
		if (StrEqual(voteType, "ScrambleTeams", false)) {
			ReplySource oldReplySource = SetCmdReplySource(SM_REPLY_TO_CHAT);
			CastVoteScramble(client);
			SetCmdReplySource(oldReplySource);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

static Action cmd_MpScrambleTeams(int client, const char[] command, int argc) {
	if (client == 0) {
		// mp_scrambleteams normally works by queuing a scramble and restarting the round.
		// The scramble is already blocked by our hook, so we just queue a scramble here.
		QueueRoundScramble();
		notifyScramble();
	}
	return Plugin_Continue;
}

static AdminScrambleOpts parseAdminScrambleOpt(char[] arg) {
	if (StrEqual(arg, "restart", false)) {
		return AdminScrambleOpt_Restart;
	} else if (StrEqual(arg, "respawn", false)) {
		return AdminScrambleOpt_Respawn;
	} else if (StrEqual(arg, "retain", false)) {
		return AdminScrambleOpt_Retain;
	} else {
		return AdminScrambleOpt_None;
	}
}

static Action cmd_Scramble(int client, int args) {
	if (IsInPostRound() || IsInWaitingForPlayers()) {
		adminQueueRoundScramble(client);
	} else {
		AdminScrambleOpts opts = AdminScrambleOpt_None;
		{
			char arg[16];
			for (int i = 1; i <= args; ++i) {
				GetCmdArg(i, arg, sizeof(arg));
				AdminScrambleOpts parsedOpt = parseAdminScrambleOpt(arg);
				if (parsedOpt == AdminScrambleOpt_None) {
					SS_ReplyToCommand(client, "\x07%06X%t", g_MessageFailureColorCode, "AdminScrambleUnknownOption", arg);
					return Plugin_Handled;
				}
				opts |= parsedOpt;
			}
		}

		if ((opts & AdminScrambleOpt_Restart) != AdminScrambleOpt_None) {
			if (IsInSetup()) {
				LogAction(client, -1, "\"%L\" restarted the round and performed immediate team scramble", client);
				ShowActivity2(client, ACTION_TAG, "%t", "AdminScrambleRestart");
				RestartSetupScramble();
			} else {
				SS_ReplyToCommand(client, "\x07%06X%t", g_MessageFailureColorCode, "AdminScrambleRestartSetupOnly");
			}
		} else {
			LogAction(client, -1, "\"%L\" performed immediate team scramble", client);
			ShowActivity2(client, ACTION_TAG, "%t", "AdminScramble");
			RespawnMode respawnMode = RespawnMode_Dont;
			if (IsInPreRound()) {
				respawnMode = RespawnMode_Normal;
			} else if ((opts & AdminScrambleOpt_Retain) != AdminScrambleOpt_None || IsInSetup()) {
				respawnMode = RespawnMode_Retain;
			} else if ((opts & AdminScrambleOpt_Respawn) != AdminScrambleOpt_None) {
				respawnMode = RespawnMode_Normal;
			}
			PerformScramble(respawnMode);
		}
	}

	return Plugin_Handled;
}

static Action cmd_ScrambleRound(int client, int args) {
	adminQueueRoundScramble(client);
	return Plugin_Handled;
}

static void adminQueueRoundScramble(int client) {
	if (QueueRoundScramble()) {
		LogAction(client, -1, "\"%L\" queued team scramble for next round", client);
		ShowActivity2(client, ACTION_TAG, "%t", "AdminScrambleRound");
	} else {
		SS_ReplyToCommand(client, "\x07%06X%t", g_MessageSuccessColorCode, "ScrambleRoundAlreadyQueued");
	}
}

static Action cmd_TeamStats(int client, int args) {
	if (client == 0 || canClientSeeTeamStats(client)) {
		PrintTeamStats(client);
	} else {
		SS_ReplyToCommand(client, "\x07%06X%t", g_MessageFailureColorCode, "TeamStatsNoPerm");
	}
	return Plugin_Handled;
}

static Action cmd_VoteScramble(int client, int args) {
	CastVoteScramble(client);
	return Plugin_Handled;
}

static Action event_PlayerTeam_Pre(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	int team = event.GetInt("team");
	int oldTeam = event.GetInt("oldteam");
	if (team != oldTeam) {
		if (team == TEAM_SPECTATOR || team == TEAM_UNASSIGNED)
		{
			PauseClientScoring(client);
		}
		else
		{
			ResumeClientScoring(client);
		}
	}

	if (g_SuppressTeamSwitchMessage) {
		event.SetBool("silent", true);
	}

	return Plugin_Continue;
}

static Action event_PlayerDeath_Post(Event event, const char[] name, bool dontBroadcast) {
	if (!IsInWaitingForPlayers() && !IsInPostRound()) {
		int victim = GetClientOfUserId(event.GetInt("userid"));
		int attacker = GetClientOfUserId(event.GetInt("attacker"));

		if (attacker != 0) {
			int victimTeam = GetClientTeam(victim);
			int attackerTeam = GetClientTeam(attacker);
			if (victimTeam != attackerTeam) {
				AutoScrambleTeamFrag(attackerTeam);
			}
		}
	}

	return Plugin_Continue;
}

static Action event_RoundStart_Post(Event event, const char[] name, bool dontBroadcast) {
	if (!IsInWaitingForPlayers()) {
		if(g_MapStartScramble){
			MapStartScramble();
		}
		else if (IsRoundScrambleQueued()) {
			RoundScramble();
		} else if (SwitchedTeamsThisRound()) {
			AutoScrambleSwitchedTeams();
		}
	}
	return Plugin_Continue;
}

static Action event_RoundWin_Post(Event event, const char[] name, bool dontBroadcast) {
	UpdateScoreCache();
	int winningTeam = event.GetInt("team");
	bool fullRound = event.GetBool("full_round");

	bool canAutoScramble = AutoScrambleRoundFinished(winningTeam, fullRound);

	if (canAutoScramble && !IsRoundScrambleQueued()) {
		AutoScrambleReason autoScrambleReason = MaybeAutoScramble(winningTeam);
		if (autoScrambleReason != AutoScrambleReason_None) {
			AutoScrambleRound(autoScrambleReason);
		}
	}

	if (IsRoundScrambleQueued()) {
		notifyScramble();
	}

	return Plugin_Continue;
}

static Action event_VipAssigned_Post(Event event, const char[] name, bool dontBroadcast){
	int client = GetClientOfUserId(event.GetInt("userid"));
	int team = event.GetInt("team");
	int oldVip = GetTeamVIP(team);
	SetTeamVIP(team, client);
	if(g_DebugLog){
		DebugLog("VIP for team %d changed from %d to %d", team, oldVip, client);
	}
	if(oldVip != 0 && IsClientConnected(oldVip)){
		ResumeClientScoring(oldVip);
	}
	PauseClientScoring(client);
	return Plugin_Continue;
}

void InitConnectedClient(int client) {
	g_ClientScrambleVote[client] = false;
	InitClientScore(client);
}

void InitInGameClient(int client) {
	g_ClientLastTime[client] = GetGameTime();
	InitClientBuddies(client);
	int id = GetSteamAccountID(client, true);
	if(id != 0){
		char key[32];
		IntToString(id, key, 32);
		DebugLog("key is %s", key);
		int playScore = 0;
		float playTime = 0.0;
		if(g_LastMapUserIdScores.ContainsKey(key)){
			DataPack userdata;
			g_LastMapUserIdScores.GetValue(key, userdata);
			userdata.Reset();
			playScore = userdata.ReadCell();
			playTime = userdata.ReadFloat();
			if(g_DebugLog){
				DebugLog("Loaded %s: %d/%f", key, playScore, playTime);
			}
			CloseHandle(userdata);
		}
		SetClientScoring(client, playScore, playTime);
	}
}

public void OnAllPluginsLoaded() {
	g_HLCEApiAvailable = LibraryExists("hlxce-sm-api");
	if(g_DebugLog){
		DebugLog("OnAllPluginsLoaded \"%i\"", g_ConVar_ScoreMethod.IntValue);
	}
	InitScoreMethod(view_as<ScoreMethod>(g_ConVar_ScoreMethod.IntValue));
	
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "hlxce-sm-api")) {
		g_HLCEApiAvailable = true;
	}
}

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "hlxce-sm-api")) {
		g_HLCEApiAvailable = false;
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	MarkNativeAsOptional("HLXCE_IsClientReady");
	MarkNativeAsOptional("HLXCE_GetPlayerData");
	return APLRes_Success;
}

public void OnClientPutInServer(int client) {
	InitInGameClient(client);
}

public void OnClientConnected(int client) {
	if (!IsFakeClient(client)) {
		++g_HumanClients;
	}

	InitConnectedClient(client);
}

public void OnClientDisconnect(int client) {
	PauseClientScoring(client);
	int id = GetSteamAccountID(client, true);
	if(id != 0){
		DataPack userdata = new DataPack();
		userdata.WriteCell(g_ClientPlayScore[client]);
		userdata.WriteFloat(g_ClientPlayTime[client]);
		char key[32];
		IntToString(id, key, 32);
		g_LastMapUserIdScores.SetValue(key, userdata);
		if(g_DebugLog){
			DebugLog("Saved %s: %d/%f", key, g_ClientPlayScore[client], g_ClientPlayTime[client]);
		}
	}
	if (!IsFakeClient(client)) {
		--g_HumanClients;
		if (g_ClientScrambleVote[client]) {
			g_ClientScrambleVote[client] = false;
			--g_ScrambleVotes;
		}
		UpdateVoteScramblePassStatus();
	}
}

public void TF2_OnWaitingForPlayersStart() {
	ResetScrambleVotes();
	AutoScrambleGameStart();
	AutoScrambleReset();
	g_RoundScrambleQueued = false;
	g_ScrambleVoteScrambleTime = 0.0;
}

void MapStartScramble(){
	g_MapStartScramble = false;

	int sums[TEAM_MAX_PLAY];
	float ratios[TEAM_MAX_PLAY];
	ComputeTeamStats(sums, ratios);
	float ratioThreshold = 1.0/GetPlayTeamCount() * g_ScrambleOnLoadRatio;
	for (int i = 0; i < TEAM_MAX_PLAY; i++){
		if(g_DebugLog){
			DebugLog("Team %d has score %d and ratio %f. Compare to threshold %f", i+2, sums[i], ratios[i], ratioThreshold);
		}
		if(ratios[i] > ratioThreshold && ratios[i] < 1.0){ //if ratio is 1 for a team then we are dealing with invalid data for other teams
			SS_PrintToChatAll(0, "\x07%06X%t", g_MessageNotificationColorCode, "MapStartScramble");
			RoundScramble();
			break;
		}
	}

	if(g_DebugLog){
		DebugLog("Resetting scores");
	}
	g_LastMapUserIdScores.Clear();
	for (int i = 1; i <= MaxClients; ++i){
		SetClientScoring(i, 0, 0.0);
	}
}

static MRESReturn hook_GameRules_ShouldScramble(DHookReturn hReturn) {
	// We don't ever want vanilla scrambles to take place.
	DHookSetReturn(hReturn, false);
	return MRES_Supercede;
}

/**
 * Retrieves the number of seconds that a given client has been on their current team.
 */
float GetClientTimeOnTeam(int client) {
	return GetGameTime() - g_ClientLastTime[client];
}

static void notifyScramble() {
	Event event = CreateEvent("teamplay_alert");
	if (event != null) {
		event.SetInt("alert_type", 0);
		event.Fire();
	}
}

static bool canClientSeeTeamStats(int client) {
	if (!IsFakeClient(client)) {
		int adminFlags = GetUserFlagBits(client);
		return (adminFlags & s_TeamStatsAdminFlags) == s_TeamStatsAdminFlags || (adminFlags & ADMFLAG_ROOT) != 0;
	} else {
		return false;
	}
}

void ResetScrambleVotes() {
	for (int i = 1; i <= MaxClients; ++i) {
		g_ClientScrambleVote[i] = false;
	}
	g_ScrambleVotes = 0;
}

bool UpdateVoteScramblePassStatus(int lastVoteClient = 0) {
	if (!IsRoundScrambleQueued() && g_ScrambleVotes >= 1 && g_ScrambleVotes >= GetRequiredScrambleVotes()) {
		HandleVoteScramble(lastVoteClient);
		return true;
	} else {
		return false;
	}
}

void HandleVoteScramble(int passingClient = 0) {
	g_ScrambleVotePassed = true;
	ResetScrambleVotes();
	if (passingClient != 0) {
		char clientName[MAX_NAME_LENGTH_COLORED + 1];
		GetClientNameTeamColored(passingClient, g_MessageNotificationColorCode, clientName, sizeof(clientName));
		SS_PrintToChatAll(0, "\x07%06X%t \x07%06X%t", g_MessageNotificationColorCode, "CastScrambleVote", clientName, g_MessageSuccessColorCode, "ScrambleVotePassed");
	} else {
		SS_PrintToChatAll(0, "\x07%06X%t", g_MessageSuccessColorCode, "ScrambleVotePassed");
	}

	if (IsInPreRound()) {
		SS_PrintToChatAll(0, "\x07%06X%t", g_MessageNotificationColorCode, "ScrambleImmediate");
		PerformScramble(RespawnMode_Normal);
	} else if (IsInSetup()) {
		SS_PrintToChatAll(0, "\x07%06X%t", g_MessageNotificationColorCode, "ScrambleImmediate");
		if (g_ScrambleVoteRestartSetup) {
			RestartSetupScramble();
		} else {
			PerformScramble(RespawnMode_Retain);
		}
	} else {
		SS_PrintToChatAll(0, "\x07%06X%t", g_MessageNotificationColorCode, "ScrambleNextRound");
		QueueRoundScramble();
	}
}

void CastVoteScramble(int client) {
	//TEMP FIX TO REPORTED CRASHES POST 2.2
	if (GetClientTeam(client) <= 1){
		return;
	}
	if (!IsFakeClient(client)) {
		if (IsRoundScrambleQueued()) {
			SS_ReplyToCommand(client, "\x07%06X%t", g_MessageSuccessColorCode, "ScrambleRoundAlreadyQueued");
		} else if (!g_ScrambleVoteEnabled) {
			SS_ReplyToCommand(client, "\x07%06X%t", g_MessageFailureColorCode, "ScrambleVoteDisabled");
		} else if (IsInWaitingForPlayers()) {
			SS_ReplyToCommand(client, "\x07%06X%t", g_MessageFailureColorCode, "ScrambleVoteWaitingForPlayers");
		} else if (g_ScrambleVoteScrambleTime != 0.0 && g_ScrambleVoteScrambleTime + g_ScrambleVoteCooldown >= GetGameTime()) {
			float secondsToAvailable = g_ScrambleVoteScrambleTime + g_ScrambleVoteCooldown - GetGameTime();
			char secondsToAvailableString[32];
			FormatRoundedFloat(secondsToAvailableString, sizeof(secondsToAvailableString), secondsToAvailable, 2);
			SS_ReplyToCommand(client, "\x07%06X%t", g_MessageFailureColorCode, "ScrambleVoteCooldown", secondsToAvailableString);
		}  else {
			if (!g_ClientScrambleVote[client]) {
				g_ClientScrambleVote[client] = true;
				++g_ScrambleVotes;

				if (!UpdateVoteScramblePassStatus(client)) {
					char clientName[MAX_NAME_LENGTH_COLORED + 1];
					GetClientNameTeamColored(client, g_MessageNotificationColorCode, clientName, sizeof(clientName));
					int requiredVotes = GetRequiredScrambleVotes();
					SS_PrintToChatAll(client, "\x07%06X%t \x07%06X%t", g_MessageNotificationColorCode, "CastScrambleVote", clientName, g_MessageInformationColorCode, "ScrambleVoteStatus", g_ScrambleVotes, requiredVotes);
				}
			} else {
				SS_ReplyToCommand(client, "\x07%06X%t", g_MessageFailureColorCode, "AlreadyCastScrambleVote");
			}
		}
	}
}

int GetRequiredScrambleVotes() {
	int required = RoundToCeil(float(g_HumanClients) * g_ScrambleVoteRatio);
	if (required < 1) {
		required = 1;
	}
	return required;
}

/**
 * Checks if a given client should be scrambled.
 */
bool ShouldScrambleClient(int client) {
	int team = GetClientTeam(client);
	if (team == TEAM_UNASSIGNED) {
		// Never try to scramble unassigned clients
		return false;
	} else if (team == TEAM_SPECTATOR) {
		if (IsFakeClient(client)) {
			// Spectating bots are not to be scrambled.
			return false;
		} else {
			// Only scramble spectators if they have not been spectating for a significant period of time.
			return g_SpecTimeout < 0.0 || GetClientTimeOnTeam(client) < g_SpecTimeout;
		}
	} else {
		// All other clients should participate in a scramble.
		return true;
	}
}

enum struct ClientRetainInfo {
	bool retainMedigunCharge;
	float medigunCharge;

	void StoreClient(int client) {
		int medigun = GetClientMedigun(client);
		if (IsValidEntity(medigun)) {
			this.retainMedigunCharge = true;
			this.medigunCharge = GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel");
		}
	}

	void LoadClient(int client) {
		if (this.retainMedigunCharge) {
			int medigun = GetClientMedigun(client);
			if (IsValidEntity(medigun)) {
				SetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel", this.medigunCharge);
			}
		}
	}
}

void PauseClientScoring(int client){
	if(g_ClientIsTracking[client])
	{
		UpdateClientScoreTime(client);
		g_ClientIsTracking[client] = false;
		if (g_DebugLog) {
			DebugLog("Paused time tracking for %d (%d/%f)", client, g_ClientPlayScore[client], g_ClientPlayTime[client]);
		}
	}
}

void ResumeClientScoring(int client){
	if(!g_ClientIsTracking[client]){
		UpdateClientScoreTime(client);
		g_ClientIsTracking[client] = true;
		if (g_DebugLog) {
			DebugLog("Resumed time tracking for %d (%d/%f)", client, g_ClientPlayScore[client], g_ClientPlayTime[client]);
		}
	}
}

void SetClientScoring(int client, int score, float time){
	UpdateClientScoreTime(client);
	g_ClientPlayTime[client] = time;
	g_ClientPlayScore[client] = score;
	if (g_DebugLog) {
		DebugLog("Set score/time of %d to %d/%f", client, score, time);
	}
}

void UpdateClientScoreTime(int client){
	int gameScore = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iTotalScore", _, client);
	float gameTime = GetGameTime(); 
	if(g_ClientIsTracking[client]){
		g_ClientPlayTime[client] += (gameTime - g_ClientLastTime[client]);
		g_ClientPlayScore[client] += (gameScore - g_ClientLastScore[client]);
	}
	g_ClientLastTime[client] = gameTime;
	g_ClientLastScore[client] = gameScore;
}

bool MoveClientTeam(int client, int team, RespawnMode respawnMode) {
	if (GetClientTeam(client) != team) {
		if (g_DebugLog) {
			char teamName[MAX_TEAM_NAME_LENGTH];
			GetTeamName(team, teamName, sizeof(teamName));
			DebugLog("Moving %N to team %s", client, teamName);
		}

		// Client who have recently joined will sometimes have no class.
		if (TF2_GetPlayerClass(client) == TFClass_Unknown) {
			TFClassType randomClass = view_as<TFClassType>(GetRandomInt(1, 9));
			TF2_SetPlayerClass(client, randomClass);
		}

		switch (respawnMode) {
			case RespawnMode_Dont: {
				ChangeClientTeam(client, team);
			}
			case RespawnMode_Normal: {
				ChangeClientTeamRespawn(client, team);
			}
			case RespawnMode_Retain: {
				ClientRetainInfo retainInfo;
				retainInfo.StoreClient(client);
				ChangeClientTeamRespawn(client, team);
				retainInfo.LoadClient(client);
			}
			case RespawnMode_Reset: {
				RemoveClientOwnedEntities(client);
				ChangeClientTeamRespawn(client, team);
			}
		}
		return true;
	} else {
	if (respawnMode == RespawnMode_Reset) {
			RemoveClientOwnedEntities(client);
			TF2_RespawnPlayer(client);
		}
		return false;
	}
}

int ComputeTeamStats(int sums[TEAM_MAX_PLAY], float ratios[TEAM_MAX_PLAY]) {
	int sumTotal = 0;

	int clients[MAXPLAYERS];
	int clientCount = 0;

	// Gather up the clients that we will be scoring.
	for (int i = 1; i <= MaxClients; ++i) {
		if (IsClientInGame(i) && ShouldScrambleClient(i)) {
			clients[clientCount++] = i;
		}
	}
	int clientScores[MAXPLAYERS];
	ScoreClients(clients, clientScores, clientCount);

	for (int i = 0; i < clientCount; ++i) {
		int team = GetClientTeam(clients[i]);
		if (team >= TEAM_FIRST_PLAY) {
			int score = clientScores[i];
			sumTotal += score;
			sums[team - TEAM_FIRST_PLAY] += score;
		}
	}

	for (int i = 0; i < TEAM_MAX_PLAY; ++i) {
		if (sumTotal != 0) {
			ratios[i] = float(sums[i]) / sumTotal;
		} else {
			ratios[i] = 1.0 / GetPlayTeamCount();
		}
	}

	return sumTotal;
}

void PrintTeamStats(int client) {
	int teamScoreSums[TEAM_MAX_PLAY];
	float teamScoreRatios[TEAM_MAX_PLAY];
	ComputeTeamStats(teamScoreSums, teamScoreRatios);

	SS_ReplyToCommand(client, "\x07%06X%t", g_MessageInformationColorCode, "TeamStatsHeader");

	char teamName[24];
	char teamScoreRatioStr[64];
	for (int i = 0; i < GetPlayTeamCount(); ++i) {
		int team = i + TEAM_FIRST_PLAY;
		GetTeamShortName(team, teamName, sizeof(teamName));
		Format(teamName, sizeof(teamName), "\x07%06X%s\x07%06X", GetTeamColorCode(team), teamName, g_MessageInformationColorCode);

		FormatRoundedFloat(teamScoreRatioStr, sizeof(teamScoreRatioStr), teamScoreRatios[i] * 100, 2);
		Format(teamScoreRatioStr, sizeof(teamScoreRatioStr), "%s%%", teamScoreRatioStr);
		SS_ReplyToCommand(client, "\x07%06X%t", g_MessageInformationColorCode, "TeamStats", teamName, teamScoreRatioStr, teamScoreSums[i]);
	}
}

void PrintTeamStatsToAll() {
	int teamScoreSums[TEAM_MAX_PLAY];
	float teamScoreRatios[TEAM_MAX_PLAY];
	ComputeTeamStats(teamScoreSums, teamScoreRatios);

	int recipients[MAXPLAYERS];
	int recipientCount = 0;

	for (int i = 1; i <= MaxClients; ++i) {
		if (IsClientInGame(i) && canClientSeeTeamStats(i)) {
			recipients[recipientCount++] = i;
			SS_PrintToChat(i, 0, "\x07%06X%t", g_MessageInformationColorCode, "TeamStatsHeader");
		}
	}

	if (recipientCount != 0) {
		char teamName[24];
		char teamScoreRatioStr[64];
		for (int i = 0; i < GetPlayTeamCount(); ++i) {
			int team = i + TEAM_FIRST_PLAY;
			GetTeamShortName(team, teamName, sizeof(teamName));
			Format(teamName, sizeof(teamName), "\x07%06X%s\x07%06X", GetTeamColorCode(team), teamName, g_MessageInformationColorCode);

			FormatRoundedFloat(teamScoreRatioStr, sizeof(teamScoreRatioStr), teamScoreRatios[i] * 100, 2);
			Format(teamScoreRatioStr, sizeof(teamScoreRatioStr), "%s%%", teamScoreRatioStr);
			for (int j = 0; j < recipientCount; ++j) {
				SS_PrintToChat(recipients[j], 0, "\x07%06X%t", g_MessageInformationColorCode, "TeamStats", teamName, teamScoreRatioStr, teamScoreSums[i]);
			}
		}
	}
}

bool IsRoundScrambleQueued() {
	return g_RoundScrambleQueued;
}

bool QueueRoundScramble() {
	if (g_RoundScrambleQueued) {
		return false;
	} else {
		g_RoundScrambleQueued = true;
		return true;
	}
}

void RestartSetupScramble() {
	ResetSetupTimer();
	PerformScramble(RespawnMode_Reset);
	RespawnPickups();
}

void RoundScramble() {
	PerformScramble(RespawnMode_Normal, false);
}

void PerformScramble(RespawnMode respawnMode, bool notify = true) {
	if (g_DebugLog) {
		DebugLog("Performing scramble - respawnMode=%d", respawnMode);
	}

	EmitGameSoundToAll("Announcer.AM_TeamScrambleRandom");

	// Reset auto scramble conditions.
	AutoScrambleReset();

	// We scrambled now, so don't bother scrambling next round.
	g_RoundScrambleQueued = false;
	ResetScrambleVotes();

	if (g_ScrambleVotePassed) {
		g_ScrambleVotePassed = false;
		g_ScrambleVoteScrambleTime = GetGameTime();
	}

	int clients[MAXPLAYERS];
	int clientCount = 0;

	// Gather up the clients that we will be scrambling.
	for (int i = 1; i <= MaxClients; ++i) {
		if (IsClientInGame(i) && ShouldScrambleClient(i)) {
			clients[clientCount++] = i;
		}
	}

	// Build the client teams.
	int clientTeams[MAXPLAYERS];
	{
		int teamCount = GetPlayTeamCount();
		int unbalanceLimit = g_TeamsUnbalanceLimit > 0 ? g_TeamsUnbalanceLimit : INT_MAX;

		Profiler prof = new Profiler();
		prof.Start();
		BuildScrambleTeams(g_ScrambleMethod, clients, clientTeams, clientCount, teamCount, unbalanceLimit);
		prof.Stop();
		LogMessage("Scramble built %d teams from %d clients in %f seconds", teamCount, clientCount, prof.Time);
		delete prof;
	}

	// Put the clients on their new teams.
	int movedCount = 0;
	g_SuppressTeamSwitchMessage = true;
	for (int i = 0; i < clientCount; ++i) {
		int client = clients[i];
		int clientTeam = clientTeams[i] + TEAM_FIRST_PLAY;
		if (MoveClientTeam(client, clientTeam, respawnMode)) {
			++movedCount;
		}
	}
	g_SuppressTeamSwitchMessage = false;

	if (notify) {
		notifyScramble();
	}

	// Display scramble statistics.
	float movedRatio = clientCount > 0 ? float(movedCount) / clientCount : 1.0;
	char movedPercentStr[12];
	FormatRoundedFloat(movedPercentStr, sizeof(movedPercentStr), movedRatio * 100, 2);
	Format(movedPercentStr, sizeof(movedPercentStr), "%s%%", movedPercentStr);

	SS_PrintToChatAll(0, "\x07%06X%t", g_MessageNotificationColorCode, "ScrambleResult", movedCount, clientCount, movedPercentStr);
	PrintTeamStatsToAll();
}
