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

static ConVar s_ConVar_DebugLog;
bool g_DebugLog = false;

void PluginStartDebugSystem() {
	s_ConVar_DebugLog = CreateConVar(
		"ss_debug_log", "0",
		"When non-zero verbose debugging information will be logged to a file.",
		_,
		true, 0.0,
		true, 1.0
	);
	s_ConVar_DebugLog.AddChangeHook(conVarChanged_DebugLog);
	g_DebugLog = s_ConVar_DebugLog.BoolValue;
}

static void conVarChanged_DebugLog(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_DebugLog = StringToInt(newValue) ? true : false;
}

/**
 * Logs a debug message.
 *
 * @param format        Formatting rules.
 * @param ...           Variable number of format parameters.
 */
void DebugLog(const char[] format, any ...)
{
	char buffer[1024];
	VFormat(buffer, sizeof(buffer), format, 2);
	LogMessage("%s", buffer);
}