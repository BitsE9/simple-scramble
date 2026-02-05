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

/**
 * Counts the number of unassigned buddies members of this team have.
 *
 * @param team            Team to count for
 * @param clients         Array of clients that are being assigned to teams.
 * @param clientTeams     Array teams that the clients are assigned to.
 * @param clientCount     Number of clients in the clients array.
 * @return                Number of unassigned buddies members of this team have.
 */
 
static int countTeamUnassignedBuddies(int team, int clients[MAXPLAYERS], int clientTeams[MAXPLAYERS], int clientCount) {
	int count = 0;
	for (int i = 0; i < clientCount; ++i) {
		if (clientTeams[i] == team) {
			for (int j = 0; j < clientCount; ++j)
			{
				if (clientTeams[j] == TEAM_INVALID && AreClientsBuddies(clients[i], clients[j])) {
					++count;
				}
			}
		}
	}
	return count;
}

/**
 * Collects a list of candidate teams.
 *
 * @param scrambleMethod     Scramble method that is being used to build these teams.
 * @param candidateTeams     Array to output the candidate teams to.
 * @param clients            Array of clients that are being assigned to teams.
 * @param clientTeams        Array teams that the clients are assigned to.
 * @param clientCount        Number of clients in the clients array.
 * @param teamSizes          Array containing the team sizes.
 * @param teamScores         Array containing the team scores.
 * @param teamCount          The number of teams.
 * @param teamMaxSizeDiff    The maximium size difference between teams.
 * @return                   The number of candidate teams.
 */
static int collectScrambleCandidateTeams(
	ScrambleMethod scrambleMethod,
	int candidateTeams[TEAM_MAX_PLAY],
	int clients[MAXPLAYERS],
	int clientTeams[MAXPLAYERS],
	int clientCount,
	int teamSizes[TEAM_MAX_PLAY],
	int teamScores[TEAM_MAX_PLAY],
	int teamCount,
	int teamMaxSizeDiff
) {
	// First find the smallest team.
	int minTeamSize = INT_MAX;
	for (int teamIdx = 0; teamIdx < teamCount; ++teamIdx) {
		int teamSize = teamSizes[teamIdx];
		if (teamSize < minTeamSize) {
			minTeamSize = teamSize;
		}
	}
	
	// Then collect teams that are within distance of teamMaxSizeDiff of the smallest team.
	int candidateTeamCount = 0;
	int maxTeamUnassignedBuddies = 0;
	int minTeamScore = INT_MAX;
	for (int teamIdx = 0; teamIdx < teamCount; ++teamIdx) {
		int teamSize = teamSizes[teamIdx];
		if (IsTeamEscorting(teamIdx + TEAM_FIRST_PLAY)) {
			// Teams that are escorting a VIP logically behave as if they have 1 less player.
			--teamSize;
		}

		if (teamSize - minTeamSize < teamMaxSizeDiff) {
			// When in TopToWeakestTeam mode scrap candidates every time we find a new lowest score.
			if (scrambleMethod == ScrambleMethod_TopToWeakestTeam) {
				if (teamScores[teamIdx] < minTeamScore) {
					candidateTeamCount = 0;
					maxTeamUnassignedBuddies = 0;
					minTeamScore = teamScores[teamIdx];
				} else if (teamScores[teamIdx] > minTeamScore) {
					// Skip teams with scores greater than the minimum.
					continue;
				}
			}

			// This unassigned buddy check becomes exponentially expensive as the number of clients increases.
			// It is however reasonably fast up to 32 players which is alright for now.
			int unassignedBuddiesForTeam = countTeamUnassignedBuddies(teamIdx, clients, clientTeams, clientCount);
			if (unassignedBuddiesForTeam > maxTeamUnassignedBuddies) {
				candidateTeams[0] = teamIdx;
				candidateTeamCount = 1;
				maxTeamUnassignedBuddies = unassignedBuddiesForTeam;
			} else if (unassignedBuddiesForTeam == maxTeamUnassignedBuddies) {
				candidateTeams[candidateTeamCount++] = teamIdx;
			}
		}
	}
	return candidateTeamCount;
}

/**
 * Collects a list of candidate clients.
 *
 * @param scrambleMethod       Scramble method that is being used to build these teams.
 * @param clientCandidates     Array to output the candidate clients to.
 * @param unassignedClients    Array of unassigned client indices.
 * @param clientTeams          Array teams that the clients are assigned to.
 * @param clientScores         Array scores that clients have.
 * @param clientCount          Number of clients in the clients array.
 * @param teamCount            The number of teams.
 * @return                     The number of candidate clients.
 */
static int collectScrambleCandidateClients(
	ScrambleMethod scrambleMethod,
	int clientCandidates[MAXPLAYERS],
	ArrayList unassignedClients,
	int teamIdx,
	const int clients[MAXPLAYERS],
	const int clientTeams[MAXPLAYERS],
	const int clientScores[MAXPLAYERS],
	int clientCount,
	int teamCount
) {
	int clientCandidateCount = 0;
	int clientCandidateMaxDesire = INT_MIN;
	int clientCandidateMaxScore = INT_MIN;
	for (int unassignedClientIdx = 0; unassignedClientIdx < unassignedClients.Length; ++unassignedClientIdx) {
		int clientIdx = unassignedClients.Get(unassignedClientIdx);
		
		// Only select the top players in TopToWeakestTeam mode
		if (scrambleMethod == ScrambleMethod_TopToWeakestTeam) {
			if (clientScores[clientIdx] > clientCandidateMaxScore) {
				clientCandidateCount = 0;
				clientCandidateMaxDesire = INT_MIN;
				clientCandidateMaxScore = clientScores[clientIdx];
			} else if (clientScores[clientIdx] < clientCandidateMaxScore) {
				continue;
			}
		}

		int client = clients[clientIdx];

		int desire = scoreClientTeamDesirability(client, teamIdx, clients, clientTeams, clientCount, teamCount);
		if (desire > clientCandidateMaxDesire) {
			clientCandidates[0] = unassignedClientIdx;
			clientCandidateCount = 1;
			clientCandidateMaxDesire = desire;
		} else if (desire == clientCandidateMaxDesire) {
			clientCandidates[clientCandidateCount++] = unassignedClientIdx;
		}
	}

	if (g_DebugLog) {
		DebugLog("Candidates for team %d (desire: %d, score: %d):", teamIdx, clientCandidateMaxDesire, clientCandidateMaxScore);
		for (int i = 0; i < clientCandidateCount; ++i) {
			int clientIdx = unassignedClients.Get(clientCandidates[i]);
			DebugLog("+ %N", clients[clientIdx]);
		}
	}

	return clientCandidateCount;
}

/**
 * Determines how much a client desires to be on a given team.
 *
 * @param client         Client to score for.
 * @param team           Team to score for.
 * @param clients        Array of client indices
 * @param clientTeams    Array of client teams.
 * @param clientCount    The number of clients in the clients array.
 * @param teamCount      The number of teams being built.
 * @return               Score representing how much the client desires the given team.
 */
static int scoreClientTeamDesirability(int client, int team, const int clients[MAXPLAYERS], const int clientTeams[MAXPLAYERS], int clientCount, int teamCount) {
	int teamBuddyBias = teamCount * 2;
	int score = 0;
	for (int clientIdx = 0; clientIdx < clientCount; ++clientIdx) {
		int otherClient = clients[clientIdx];
		if (AreClientsBuddies(client, otherClient)) {
			if (clientTeams[clientIdx] == team) {
				// Every buddy on this team makes this team more desirable.
				score += teamBuddyBias;
				if (g_DebugLog) {
					DebugLog("Candidate %N gains %d points for buddy on this team", client, teamBuddyBias);
				}
			} else if (clientTeams[clientIdx] == TEAM_INVALID) {
				// Every unassigned buddy makes us more eager to be assigned a team.
				score += 1;
				if (g_DebugLog) {
					DebugLog("Candidate %N gains 1 point for unassigned buddy", client);
				}
			} else {
				// Every buddy on a different team makes this team less desirable.
				score -= teamBuddyBias;
				if (g_DebugLog) {
					DebugLog("Candidate %N loses %d points for buddy on different team", client, teamBuddyBias);
				}
			}
		}
	}
	return score;
}

/**
 * Creates an array list consisting of indices up to a max.
 *
 * @param maxIndex       The maximum index.
 * @param extraBlocks    Extra blocks in the array.
 * @return               Array consisting of indices up to the max.
 */
static ArrayList createIndicesArray(int maxIndex, int extraBlocks = 0) {
	ArrayList arr = new ArrayList(1 + extraBlocks, maxIndex);
	for (int i = 0; i < maxIndex; ++i) {
		arr.Set(i, i);
	}
	return arr;
}

/**
 * Shuffles the elements of an ArrayList.
 *
 * @param arr    ArrayList to shuffle.
 * @noreturn
 */
/*static void shuffleArray(ArrayList arr) {
	for (int i = 0; i < arr.Length; ++i) {
		int j = GetRandomInt(0, arr.Length - 1);
		arr.SwapAt(i, j);
	}
}*/

/**
 * Builds teams by shuffling.
 *
 * @param scrambleMethod    Scramble method to use to build teams.
 * @param clients           Array of clients that we're building teams for.
 * @param clientTeams       Array of client teams mapped to the clients array will be output to this array.
 * @param clientCount       Number of clients in the clients array.
 * @param teamCount         Number of teams to build.
 * @noreturn
 */
void BuildScrambleTeams(ScrambleMethod scrambleMethod, int clients[MAXPLAYERS], int clientTeams[MAXPLAYERS], int clientCount, int teamCount, int teamMaxSizeDiff) {
	if (g_DebugLog) {
		DebugLog("BuildScrambleTeams scrambleMethod=%d", scrambleMethod);
	}

	// Clear the teams array.
	for (int i = 0; i < clientCount; ++i) {
		clientTeams[i] = TEAM_INVALID;
	}

	// Score the clients
	int clientScores[MAXPLAYERS] = {0, ...};
	if (scrambleMethod != ScrambleMethod_Shuffle) {
		ScoreClients(clients, clientScores, clientCount);
	}

	// Build array of unassgined clients.
	ArrayList unassignedClients = createIndicesArray(clientCount);
	
	int teamSizes[TEAM_MAX_PLAY] = {0, ...};
	int teamScores[TEAM_MAX_PLAY] = {0, ...};

	while (unassignedClients.Length != 0) {
		// Find candidate teams.
		int candidateTeams[TEAM_MAX_PLAY];
		int candidateTeamCount = collectScrambleCandidateTeams(
			scrambleMethod,
			candidateTeams,
			clients,
			clientTeams,
			clientCount,
			teamSizes,
			teamScores,
			teamCount,
			teamMaxSizeDiff
		);
		int candidateTeamIdx = GetRandomInt(0, candidateTeamCount - 1);
		int teamIdx = candidateTeams[candidateTeamIdx];
		if (g_DebugLog) {
			DebugLog("Picking client for team %d (score: %d)", teamIdx, teamScores[teamIdx]);
		}

		// Find clients that most desire this team.
		int clientCandidates[MAXPLAYERS];
		int clientCandidateCount = collectScrambleCandidateClients(
			scrambleMethod,
			clientCandidates,
			unassignedClients,
			teamIdx,
			clients,
			clientTeams,
			clientScores,
			clientCount,
			teamCount
		);

		// Pick a candidate client to put on this team.
		int unassignedClientIdx = clientCandidates[GetRandomInt(0, clientCandidateCount - 1)];
		int clientIdx = unassignedClients.Get(unassignedClientIdx);
		clientTeams[clientIdx] = teamIdx;
		++teamSizes[teamIdx];
		teamScores[teamIdx] += clientScores[clientIdx];
		unassignedClients.Erase(unassignedClientIdx);

		if (g_DebugLog) {
			DebugLog("%N assigned to team %d (+score: %d)", clients[clientIdx], teamIdx, clientScores[clientIdx]);
		}
	}

	delete unassignedClients;
}
