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

enum ScoreMethod {
	ScoreMethod_GameScore = 0,
	ScoreMethod_HLXCE_Skill = 1,
};

ConVar g_ConVar_ScoreMethod;
static ConVar s_ConVar_ScorePrecisionFactor;
static ConVar s_ConVar_FallbackScore;

ScoreMethod g_ScoreMethod;
int g_ScorePrecisionFactor;
int g_FallbackScore;

int g_ClientCachedScore[MAXPLAYERS];

void PluginStartScoringSystem() {
	g_ConVar_ScoreMethod = CreateConVar(
		"ss_score_method", "0",
		"The method used to score players during a scramble.\n\t0 - Use Game Score\n\t1 - Use HLX:CE Skill",
		_,
		true, 0.0,
		true, 1.0
	);
	g_ConVar_ScoreMethod.AddChangeHook(conVarChanged_ScoreMethod);
	
	s_ConVar_ScorePrecisionFactor = CreateConVar(
		"ss_score_precision_factor", "1",
		"All scores are rounded to the nearest multiple of this value when evaluated. Smaller numbers result in better balanced teams while larger numbers offer more opportunities for players to be viewed as equal.",
		_,
		true, 1.0
	);
	s_ConVar_ScorePrecisionFactor.AddChangeHook(conVarChanged_ScorePrecisionFactor);
	g_ScorePrecisionFactor = s_ConVar_ScorePrecisionFactor.IntValue;
	
	s_ConVar_FallbackScore = CreateConVar(
		"ss_fallback_score", "0",
		"The fallback score value given to players when no score data is available."
	);
	s_ConVar_FallbackScore.AddChangeHook(conVarChanged_BotScore);
	g_FallbackScore = s_ConVar_FallbackScore.IntValue;
}

static void conVarChanged_ScoreMethod(ConVar convar, const char[] oldValue, const char[] newValue) {
	InitScoreMethod(view_as<ScoreMethod>(StringToInt(newValue)));
}

static void conVarChanged_ScorePrecisionFactor(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_ScorePrecisionFactor = StringToInt(newValue);
}

static void conVarChanged_BotScore(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_FallbackScore = StringToInt(newValue);
}

int ScoreClient(int client) {
	int score = ScoreClientUnmodified(client);
	int modifiedScore = score;
	if (modifiedScore < 0) {
		// all score are clamped to zero to ensure correctness of math
		modifiedScore = 0;
	}
	modifiedScore += g_ScorePrecisionFactor / 2;
	modifiedScore = modifiedScore - (modifiedScore % g_ScorePrecisionFactor);
	return modifiedScore;
}

int ScoreClientUnmodified(int client) {
	int score;
	switch (g_ScoreMethod) {
		case ScoreMethod_GameScore:
			score = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iTotalScore", _, client);
		default:
			score = g_ClientCachedScore[client];
	}
	return score;
}

void InitClientScore(int client) {
	g_ClientCachedScore[client] = g_FallbackScore;
	switch (g_ScoreMethod) {
		case ScoreMethod_HLXCE_Skill: {
			if (HLXCE_IsClientReady(client)) {
				HLXCE_GetPlayerData(client);
			}
		}
	}
}

void UpdateScoreCache() {
	switch (g_ScoreMethod) {
		case ScoreMethod_HLXCE_Skill:
			updateScoreCache_HLXCE();
	}
}

void InitScoreMethod(ScoreMethod scoreMethod) {
	if (g_ScoreMethod != scoreMethod) {
		g_ScoreMethod = scoreMethod;
		switch (g_ScoreMethod) {
			case ScoreMethod_HLXCE_Skill:
				initScoreMethod_HLXCE();
		}
	}
}

static void updateScoreCache_HLXCE() {
	for (int i = 1; i <= MaxClients; ++i) {
		if (HLXCE_IsClientReady(i)) {
			HLXCE_GetPlayerData(i);
		}
	}
}

static void initScoreMethod_HLXCE() {
	if (g_HLCEApiAvailable) {
		updateScoreCache_HLXCE();
	} else {
		LogMessage("hlxce-sm-api is missing - falling back to game score method");
		InitScoreMethod(ScoreMethod_GameScore);			
	}
}

public int HLXCE_OnClientReady(int client) {
	HLXCE_GetPlayerData(client);
}

public int HLXCE_OnGotPlayerData(int client, const PData[HLXCE_PlayerData]) {
	if (g_ScoreMethod == ScoreMethod_HLXCE_Skill) {
		g_ClientCachedScore[client] = PData[PData_Skill];
		if (g_DebugLog) {
			LogMessage("%N fetched skill score %d from HLX:CE", client, g_ClientCachedScore[client]);
		}
	}
}