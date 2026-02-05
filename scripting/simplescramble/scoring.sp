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

enum ScoreMethod {
	ScoreMethod_GameScore = 0,
	ScoreMethod_HLXCE_Skill = 1,
	ScoreMethod_GameScore_Time = 2
};

ConVar g_ConVar_ScoreMethod;
static ConVar s_ConVar_ScorePrecisionFactor;
static ConVar s_ConVar_FallbackScore;

ScoreMethod g_ScoreMethod;
int g_ScorePrecisionFactor;
int g_FallbackScore;

ConVar g_ConVar_NewPlayerThreshold;
float g_NewPlayerThreshold;

int g_ClientCachedScore[MAXPLAYERS];

void PluginStartScoringSystem() {
	g_ConVar_ScoreMethod = CreateConVar(
		"ss_score_method", "2",
		"The method used to score players during a scramble.\n\t0 - Use Game Score\n\t1 - Use HLX:CE Skill\n\t2 - Use Game Score per 10 minutes",
		_,
		true, 0.0,
		true, 2.0
	);
	g_ConVar_ScoreMethod.AddChangeHook(conVarChanged_ScoreMethod);
	if (g_DebugLog){
		DebugLog("PluginStartScoringSystem \"%i\"", g_ConVar_ScoreMethod.IntValue);
	}

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

	g_ConVar_NewPlayerThreshold = CreateConVar(
		"ss_new_threshold", "300.0",
		"The amount of time after joining where a player's effective score for scrambles incorporates the server's average score.",
		_,
		true, 0.0,
		false, 2.0
	);
	
	g_ConVar_NewPlayerThreshold.AddChangeHook(conVarChanged_NewPlayerThreshold);
	g_NewPlayerThreshold = g_ConVar_NewPlayerThreshold.FloatValue;
}

static void conVarChanged_NewPlayerThreshold(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_NewPlayerThreshold = StringToFloat(newValue);
}

static void conVarChanged_ScoreMethod(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(g_DebugLog){
		DebugLog("conVarChanged_ScoreMethod \"%s\"", newValue);
	}
	InitScoreMethod(view_as<ScoreMethod>(StringToInt(newValue)));
}

static void conVarChanged_ScorePrecisionFactor(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_ScorePrecisionFactor = StringToInt(newValue);
}

static void conVarChanged_BotScore(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_FallbackScore = StringToInt(newValue);
}

int ScoreClient(int client) {
	int modifiedScore = ScoreClientUnmodified(client);
	if (modifiedScore < 0) {
		// all score are clamped to zero to ensure correctness of math
		modifiedScore = 0;
	}
	modifiedScore += g_ScorePrecisionFactor / 2;
	modifiedScore = modifiedScore - (modifiedScore % g_ScorePrecisionFactor);
	return modifiedScore;
}

float GetClientCurrentPlayTime(int client)
{
	if(g_ClientIsTracking[client])
	{
		return (g_ClientPlayTime[client] + GetClientTimeOnTeam(client));
	}
	return g_ClientPlayTime[client]
}

int GetClientScoreTime(int client){
	UpdateClientScoreTime(client);
	return RoundToNearest((g_ClientPlayScore[client] * 600) / g_ClientPlayTime[client]);
}


int ScoreClientUnmodified(int client) {
	int score;
	switch (g_ScoreMethod) {
		case ScoreMethod_GameScore:
			score = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iTotalScore", _, client);
		case ScoreMethod_GameScore_Time:
			score = GetClientScoreTime(client);
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

/**
 * Interpolates two score values linearly
 * 
 * @param scoreA	A score value
 * @param scoreB	Another score value
 * @param weightA	How much do we favour scoreA? 0.5 is exactly between A and B
 */
int InterpolateScoreLinear(int scoreA, int scoreB, float weightA){
	return RoundToNearest(scoreA * weightA + scoreB * (1-weightA)); //use a linear interpolation
}

const float PI = 3.14159265359;

/**
 * Interpolates two score values smoothly using trig
 * 
 * @param scoreA	A score value
 * @param scoreB	Another score value
 * @param weightA	How much do we favour scoreA? 0.5 is exactly between A and B
 */
int InterpolateScoreSine(int scoreA, int scoreB, float weightA){
	float newWeightA = 0.5*(1+Sine((weightA * PI)-(PI/2))); //use a segment of sine to smoothly blend the two values
	return InterpolateScoreLinear(scoreA, scoreB, newWeightA);
}

void ScoreClients(int clients[MAXPLAYERS], int clientScores[MAXPLAYERS], int clientCount){
	int scoreAvg = 0;
	int scoringClients = 0;
	for (int i = 0; i < clientCount; ++i) { //calculate the average while we iterate to set the scores
		int client = clients[i];
		int clientScore = ScoreClient(client);
		clientScores[i] = clientScore;
		if (GetClientCurrentPlayTime(client) >= g_NewPlayerThreshold) { //don't count new players in the average
			scoreAvg += clientScore;
			scoringClients++;
		}
	}

	if(scoringClients > 0){ //get average score for players connected longer than the threshold
		scoreAvg /= scoringClients;
		if(g_DebugLog){
			DebugLog("Average score: %d", scoreAvg);
		}
	}

	//only run the following for gamescore_time scoring
	//doing so is a bandaid but it only needs to work with this scoring method for now
	//note: this only makes sense to do for time based scoring anyway
	if (g_ScoreMethod == ScoreMethod_GameScore_Time) {
		if(g_DebugLog){
			DebugLog("Threshold: %f", g_NewPlayerThreshold);
		}
		for (int i = 0; i < clientCount; ++i) {
			int client = clients[i];
			float playTime = GetClientCurrentPlayTime(client);
			if (playTime < g_NewPlayerThreshold) {
				if(g_DebugLog){
					DebugLog("Interpolated between %d and %d", clientScores[i], scoreAvg);
				}
				clientScores[i] = InterpolateScoreSine(clientScores[i], scoreAvg, playTime/g_NewPlayerThreshold);
			}
			if(g_DebugLog){
				DebugLog("Player %N (%d/%f) assigned score of %d", client, g_ClientPlayScore[client], playTime, clientScores[i]);
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
		if(g_DebugLog){
			DebugLog("set score method \"%i\"", g_ScoreMethod);
		}
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
		if(g_DebugLog){
			DebugLog("initScoreMethod_HLXCE \"%i\"", ScoreMethod_GameScore);
		}
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
