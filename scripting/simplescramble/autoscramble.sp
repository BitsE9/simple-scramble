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

static ConVar s_ConVar_Enabled;
static ConVar s_ConVar_FullRoundsOnly;
static ConVar s_ConVar_InitialRoundCooldown;
static ConVar s_ConVar_RoundCooldown;
static ConVar s_ConVar_RequiredExtraPlayers;
static ConVar s_ConVar_RoundWinStreak;
static ConVar s_ConVar_DominationLead;
static ConVar s_ConVar_FragRatio;

static bool s_Enabled;
static bool s_FullRoundsOnly;
static int s_InitialRoundCooldown;
static int s_RoundCooldown;
static int s_RequiredExtraPlayers;
static int s_RoundWinStreak;
static int s_DominationLead;
static float s_FragRatio;

static int s_OnCooldownRounds = 0;
static int s_LastRoundWinTeam = -1;
static int s_LastRoundWinTeamConsecutive;
static int s_TeamFrags[TEAM_MAX_PLAY];

enum AutoScrambleReason {
	AutoScrambleReason_None,
	AutoScrambleReason_RoundWinStreak,
	AutoScrambleReason_DominationLead,
	AutoScrambleReason_FragRatio,
}

void PluginStartAutoScrambleSystem() {
	s_ConVar_Enabled = CreateConVar(
		"ss_autoscramble_enabled", "1",
		"Auto-scramble will only occur if this is set to 1.",
		_,
		true, 0.0,
		true, 1.0
	);
	s_ConVar_Enabled.AddChangeHook(conVarChanged_Enabled);
	s_Enabled = s_ConVar_Enabled.BoolValue;

	s_ConVar_FullRoundsOnly = CreateConVar(
		"ss_autoscramble_full_rounds_only", "0",
		"Auto-scramble is only allowed to occur at the end of full rounds if set to 1.",
		_,
		true, 0.0,
		true, 1.0
	);
	s_ConVar_FullRoundsOnly.AddChangeHook(conVarChanged_FullRoundsOnly);
	s_FullRoundsOnly = s_ConVar_FullRoundsOnly.BoolValue;

	s_ConVar_InitialRoundCooldown = CreateConVar(
		"ss_autoscramble_initial_round_cooldown", "1",
		"Auto-scramble can only after this many mini-rounds have been played since the game began.",
		_,
		true, 0.0
	);
	s_ConVar_InitialRoundCooldown.AddChangeHook(conVarChanged_InitialRoundCooldown);
	s_InitialRoundCooldown = s_ConVar_InitialRoundCooldown.IntValue;

	s_ConVar_RoundCooldown = CreateConVar(
		"ss_autoscramble_round_cooldown", "1",
		"Auto-scramble can only occur after this many mini-rounds have been played since the last auto-scramble.",
		_,
		true, 0.0
	);
	s_ConVar_RoundCooldown.AddChangeHook(conVarChanged_RoundCooldown);
	s_RoundCooldown = s_ConVar_RoundCooldown.IntValue;

	s_ConVar_RequiredExtraPlayers = CreateConVar(
		"ss_autoscramble_required_extra_players", "1",
		"Auto-scramble will only occur if there are as many players as there are teams plus this amount.",
		_,
		true, 0.0
	);
	s_ConVar_RequiredExtraPlayers.AddChangeHook(conVarChanged_RequiredExtraPlayers);
	s_RequiredExtraPlayers = s_ConVar_RequiredExtraPlayers.IntValue;

	s_ConVar_RoundWinStreak = CreateConVar(
		"ss_autoscramble_round_win_streak", "3",
		"Auto-scramble if a single team wins this many full-rounds consecutively. A value of 0 will disable this check.",
		_,
		true, 0.0
	);
	s_ConVar_RoundWinStreak.AddChangeHook(conVarChanged_RoundWinStreak);
	s_RoundWinStreak = s_ConVar_RoundWinStreak.IntValue;

	s_ConVar_DominationLead = CreateConVar(
		"ss_autoscramble_domination_lead", "10",
		"Auto-scramble if the winning team has this many more dominations than the average dominations of all other teams. A value of 0 will disable this check.",
		_,
		true, 0.0
	);
	s_ConVar_DominationLead.AddChangeHook(conVarChanged_DominationLead);
	s_DominationLead = s_ConVar_DominationLead.IntValue;

	s_ConVar_FragRatio = CreateConVar(
		"ss_autoscramble_frag_ratio", "2.0",
		"Auto-scramble if the winning team's frag ratio to the average of all other team frags is greater than or equal to this. A value of 0 will disable this check.",
		_,
		true, 0.0
	);
	s_ConVar_FragRatio.AddChangeHook(conVarChanged_FragRatio);
	s_FragRatio = s_ConVar_FragRatio.FloatValue;
}

static void conVarChanged_Enabled(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_Enabled = StringToInt(newValue) ? true : false;
}

static void conVarChanged_FullRoundsOnly(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_FullRoundsOnly = StringToInt(newValue) ? true : false;
}

static void conVarChanged_InitialRoundCooldown(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_InitialRoundCooldown = StringToInt(newValue);
}

static void conVarChanged_RoundCooldown(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_RoundCooldown = StringToInt(newValue);
}

static void conVarChanged_RequiredExtraPlayers(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_RequiredExtraPlayers = StringToInt(newValue);
}

static void conVarChanged_RoundWinStreak(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_RoundWinStreak = StringToInt(newValue);
}

static void conVarChanged_DominationLead(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_DominationLead = StringToInt(newValue);
}

static void conVarChanged_FragRatio(ConVar convar, const char[] oldValue, const char[] newValue) {
	s_FragRatio = StringToFloat(newValue);
}

void AutoScrambleGameStart() {
	s_OnCooldownRounds = s_InitialRoundCooldown;
}

void AutoScrambleReset() {
	s_LastRoundWinTeam = -1;
	s_LastRoundWinTeamConsecutive = 0;
	
	for (int i = 0; i < TEAM_MAX_PLAY; ++i) {
		s_TeamFrags[i] = 0;
	}
}

bool AutoScrambleRoundFinished(int team, bool fullRound) {
	bool canScramble = s_Enabled && s_OnCooldownRounds <= 0 && (fullRound || !s_FullRoundsOnly);
	if (s_OnCooldownRounds > 0) {
		--s_OnCooldownRounds;
	}

	if (fullRound) {
		if (team >= TEAM_FIRST_PLAY) {
			int teamIdx = team - TEAM_FIRST_PLAY;
			if (teamIdx != s_LastRoundWinTeam) {
				s_LastRoundWinTeam = teamIdx;
				s_LastRoundWinTeamConsecutive = 0;
			}
			++s_LastRoundWinTeamConsecutive;
		}
	}

	if (g_DebugLog) {
		DebugLog("Team auto-scramble stats after round finished:");
		LogDebugAutoScrambleTeamStats();
		DebugLog("Auto-scramble allowed this round = %s", canScramble ? "true" : "false");
	}

	return canScramble;
}

void AutoScrambleTeamFrag(int team) {
	if (team >= TEAM_FIRST_PLAY) {
		int teamIdx = team - TEAM_FIRST_PLAY;
		++s_TeamFrags[teamIdx];
	}
}

void LogDebugAutoScrambleTeamStats() {
	DebugLog("Last round won by team %d with a win streak of %d", s_LastRoundWinTeam, s_LastRoundWinTeamConsecutive);

	int teamMask = GetPlayTeamActiveMask();
	for (int i = 0; i < TEAM_MAX_PLAY; ++i) {
		if ((teamMask & (1 << i)) == 0) {
			continue;
		}
		DebugLog("Team %d has %d frags so far", i, s_TeamFrags[i]);
	}
}

void AutoScrambleSwitchedTeams() {
	int teamMask = GetPlayTeamActiveMask();

	// Teams are cyclically rotated to the right when switched.
	
	// Find the team bounds.
	int teamFront = -1;
	int teamBack = -1;
	for (int i = 0; i < TEAM_MAX_PLAY; ++i) {
		if ((teamMask & (1 << i)) != 0) {
			if (teamFront == -1) {
				teamFront = i;
			}
			teamBack = i;
		}
	}
	
	//char teamName1[4];
	//char teamName2[4];
	
	if (teamFront != teamBack) {
		// Rotate the winning team.
		if (s_LastRoundWinTeam != -1) {
			int prevLastRoundWinTeam = s_LastRoundWinTeam;
			if (++s_LastRoundWinTeam >= TEAM_MAX_PLAY) {
				s_LastRoundWinTeam = 0;
			}
			while (s_LastRoundWinTeam != prevLastRoundWinTeam) {
				if ((teamMask & (1 << s_LastRoundWinTeam)) != 0) {
					break;
				} else {
					++s_LastRoundWinTeam;
				}
			}
			//GetTeamShortName(prevLastRoundWinTeam + TEAM_FIRST_PLAY, teamName1, sizeof(teamName1));
			//GetTeamShortName(s_LastRoundWinTeam + TEAM_FIRST_PLAY, teamName2, sizeof(teamName2));
			//PrintToChatAll("Last winner changed from %s to %s", teamName1, teamName2);
		}
		
		
		// Store the back because it's going to get overwritten.
		int teamBackFrags = s_TeamFrags[teamBack];
		
		// Loop backwards performing assignments until the front bound is hit.
		int teamLhs = teamBack;
		while (teamLhs > teamFront) {
			int teamRhs = teamLhs - 1;
			while ((teamMask & (1 << teamRhs)) == 0) {
				--teamRhs;
			}
			
			s_TeamFrags[teamLhs] = s_TeamFrags[teamRhs];
			//GetTeamShortName(teamLhs + TEAM_FIRST_PLAY, teamName1, sizeof(teamName1));
			//GetTeamShortName(teamRhs + TEAM_FIRST_PLAY, teamName2, sizeof(teamName2));
			//PrintToChatAll("%s assigned %s's frags", teamName1, teamName2);
			teamLhs = teamRhs;
		}
		s_TeamFrags[teamLhs] = teamBackFrags;
		//GetTeamShortName(teamLhs + TEAM_FIRST_PLAY, teamName1, sizeof(teamName1));
		//GetTeamShortName(teamBack + TEAM_FIRST_PLAY, teamName2, sizeof(teamName2));
		//PrintToChatAll("%s assigned %s's frags", teamName1, teamName2);
	}

	if (g_DebugLog) {
		DebugLog("Team auto-scramble stats after team rotation:");
		LogDebugAutoScrambleTeamStats();
	}
}

void GetAutoScrambleReasonTranslation(AutoScrambleReason reason, char[] dest, int destLen) {
	switch (reason) {
		case AutoScrambleReason_RoundWinStreak:
			strcopy(dest, destLen, "AutoScrambleReason_RoundWinStreak");
		case AutoScrambleReason_DominationLead:
			strcopy(dest, destLen, "AutoScrambleReason_DominationLead");
		case AutoScrambleReason_FragRatio:
			strcopy(dest, destLen, "AutoScrambleReason_FragRatio");
	}
}

void AutoScrambleRound(AutoScrambleReason reason) {
	if (QueueRoundScramble()) {
		s_OnCooldownRounds = s_RoundCooldown;
		char reasonTranslation[64];
		GetAutoScrambleReasonTranslation(reason, reasonTranslation, sizeof(reasonTranslation));
		SS_PrintToChatAll(0, "\x07%06X%t \x07%06X%t", g_MessageNotificationColorCode, "AutoScrambleNextRound", g_MessageInformationColorCode, reasonTranslation);
		if (g_DebugLog) {
			DebugLog("Auto-scramble queued - %t", reasonTranslation);
		}
	}
}

static int countTeamDominations(int teamDominations[TEAM_MAX_PLAY]) {
	for (int i = 0; i < TEAM_MAX_PLAY; ++i) {
		teamDominations[i] = 0;
	}

	int playerResource = GetPlayerResourceEntity();

	int totalSum = 0;
	for (int i = 1; i <= MaxClients; ++i) {
		if (IsClientInGame(i)) {
			int team = GetClientTeam(i);
			if (team >= TEAM_FIRST_PLAY) {
				int teamIdx = team - TEAM_FIRST_PLAY;
				int dominationCount = GetEntProp(playerResource, Prop_Send, "m_iActiveDominations", _, i);
				teamDominations[teamIdx] += dominationCount;
				totalSum += dominationCount;
			}
		}
	}

	return totalSum;
}

AutoScrambleReason MaybeAutoScramble(int winningTeam) {
	// Only scramble if there was a winner.
	int winningTeamIdx = -1;
	if (winningTeam >= TEAM_FIRST_PLAY) {
		winningTeamIdx = winningTeam - TEAM_FIRST_PLAY;
	} else {
		return AutoScrambleReason_None;
	}

	// Check if there are enough clients to scramble.
	int clientCount = 0;
	int teamCount = GetPlayTeamCount();
	int teamMask = GetPlayTeamActiveMask();
	for (int i = 1; i <= MaxClients; ++i) {
		if (IsClientInGame(i) && ShouldScrambleClient(i)) {
			++clientCount;
		}
	}
	
	if (clientCount < teamCount + s_RequiredExtraPlayers) {
		return AutoScrambleReason_None;
	}

	// Check the win streak.
	if (s_RoundWinStreak != 0 && s_LastRoundWinTeamConsecutive >= s_RoundWinStreak) {
		return AutoScrambleReason_RoundWinStreak;
	}

	// Check the domination difference.
	if (s_DominationLead != 0) {
		int teamDominationCounts[TEAM_MAX_PLAY];
		int totalDominations = countTeamDominations(teamDominationCounts);

		int winningTeamDominations = teamDominationCounts[winningTeamIdx];
		int otherTeamDominations = totalDominations - winningTeamDominations;
		int otherTeamDominationsAverage = otherTeamDominations / (teamCount - 1);

		int lead = winningTeamDominations - otherTeamDominationsAverage;
		if (lead >= s_DominationLead) {
			return AutoScrambleReason_DominationLead;
		}
	}

	// Check the frag ratio.
	if (s_FragRatio > 0.0) {
		int winningTeamFrags = s_TeamFrags[winningTeamIdx];
		int otherTeamFrags = 0;
		for (int i = 0; i < TEAM_MAX_PLAY; ++i) {
			if (i == winningTeamIdx || (teamMask & (1 << i)) == 0) {
				continue;
			}

			otherTeamFrags += s_TeamFrags[i];
		}

		int otherTeamFragsAverage = otherTeamFrags / (teamCount - 1);

		if (winningTeamFrags != 0 && otherTeamFragsAverage == 0) {
			return AutoScrambleReason_FragRatio;
		} else if (otherTeamFragsAverage != 0) {
			float ratio = float(winningTeamFrags) / otherTeamFragsAverage;
			if (ratio >= s_FragRatio) {
				return AutoScrambleReason_FragRatio;
			}
		}
	}

	return AutoScrambleReason_None;
}