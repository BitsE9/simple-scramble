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

#define INT_MAX 0x7FFFFFFF
#define INT_MIN 0x80000000

#define TEAM_INVALID -1
#define TEAM_UNASSIGNED 0
#define TEAM_SPECTATOR 1
#define TEAM_RED 2
#define TEAM_BLUE 3
#define TEAM_GREEN 4
#define TEAM_YELLOW 5
#define TEAM_FIRST_PLAY 2
#define TEAM_MAX_PLAY 4

#define MAX_TEAM_NAME_LENGTH 32
#define MAX_NAME_LENGTH_COLORED (MAX_NAME_LENGTH + 16)

#define ACTION_TAG "[SS] "
