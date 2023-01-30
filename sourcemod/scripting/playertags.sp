#pragma semicolon 1

#include <cstrike>
#include <csgo_colors>
#include <k1_playertag>
#include <scp>
#include <clientprefs>

#define CONFIG "addons/sourcemod/configs/player_tags.cfg"
#define TAG_LENGTH	64	// Максимальный размер тега


char 	g_sPrefix[64],
		g_sPlayerTag[MAXPLAYERS + 1][64],
		g_sAdminFlag[64];

bool 	g_bStats,
		g_bChat,
		g_bNoOverwrite,
		g_bIncognito[MAXPLAYERS + 1],
		g_bIncognitoForever[MAXPLAYERS + 1],
		g_bIsLateLoad = false,
		g_bJoinIncognito;

float 	g_fIncognitoTime;

enum struct Roles
{
	char SPECTATOR[64];
	char CT_TEAM[64];
	char T_TEAM[64];
	char CT_MSG[64];
	char T_MSG[64];
	char S_MSG[64];
	char DEAD[64];
}

Roles g_sChatTag[MAXPLAYERS + 1];
Roles g_sStatsTag[MAXPLAYERS + 1];

Handle g_hIncognitoTimer[MAXPLAYERS + 1];
Handle g_hCookie;

public Plugin myinfo =
{
	name = "Player Tags",
	author = "K1NG",
	version = "1.2"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("K1_PlayerIncog", Native_K1_PlayerIncog);

	g_bIsLateLoad = late;

	return APLRes_Success;
}

public int Native_K1_PlayerIncog(Handle hPlugin, int iParams)
{
	int iClient = GetNativeCell(1);

	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return 0;

	return g_bIncognito[iClient];
}

public void OnPluginStart()
{
	LoadTranslations("k1_playertags.phrases");

	KeyValues hkv = new KeyValues("PlayerTags");

	if (!hkv.ImportFromFile(CONFIG))
	{
		delete hkv;
		SetFailState("PlayerTags - Не найден файл %s ", CONFIG);
	}

	char sCommands[128], sCommandsL[12][32];

	hkv.GetString("prefix", g_sPrefix, sizeof(g_sPrefix), "[PlayerTags]");
	g_bStats = !!hkv.GetNum("stats", 1);
	g_bChat = !!hkv.GetNum("chat", 1);
	g_bNoOverwrite = !!hkv.GetNum("overwrite", 0);
	g_bJoinIncognito = !!hkv.GetNum("incognito_join", 1);
	g_fIncognitoTime = hkv.GetFloat("incognito_time", 120.0); 
	hkv.GetString("adminflag", g_sAdminFlag, sizeof(g_sAdminFlag), "a");
	hkv.GetString("incognito_cmds", sCommands, sizeof(sCommands), "");
	RegAdminCmd("sm_incognito", Command_Incognito, ReadFlagString(g_sAdminFlag), "Allows admin to toggle incognito - show default tags instead of admin tags");
	delete hkv;

	ReplaceString(sCommands, sizeof(sCommands), " ", "");

	int iCount = ExplodeString(sCommands, ",", sCommandsL, sizeof(sCommandsL), sizeof(sCommandsL[]));
	for(int i; i < iCount; i++) if(!CommandExists(sCommandsL[i]))
		RegAdminCmd(sCommandsL[i], Command_Incognito, ReadFlagString(g_sAdminFlag), "Allows admin to toggle incognito - show default tags instead of admin tags");

	HookEvent("player_team", Event_CheckTag);

	if(g_bIsLateLoad)
	{
		for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i)) OnClientPostAdminCheck(i);
		g_bIsLateLoad = false;
	}

	g_hCookie = RegClientCookie("Incognito", "Saves Incognito навсегда крч", CookieAccess_Private);
}


public void OnClientCookiesCached(int iClient)
{
    char szValue[4];
    GetClientCookie(iClient, g_hCookie, szValue, sizeof(szValue));
	if(szValue[0])
		g_bIncognitoForever[iClient] = view_as<bool>(StringToInt(szValue)); //хз мб можно только это оставить
	else
		g_bIncognitoForever[iClient] = false;
}

public Action Command_Incognito(int client, int args)
{
	if(!IsValidClient(client, false, true))
		return Plugin_Handled;

	if(g_bIncognito[client] && args == 0)
	{
		g_bIncognito[client] = false;
		g_bIncognitoForever[client] = false;
		SetClientCookie(client, g_hCookie, "0");
		DeleteTimer(client);

		CGOPrintToChat(client, "%s%T", g_sPrefix, "playertags_incognito_off", client);
	}
	else
	{
		g_bIncognito[client] = true;

		float fIncognitoTime = g_fIncognitoTime;

		if(args) 
		{
			char sArgs[10];
			GetCmdArg(1, sArgs, sizeof(sArgs));
			fIncognitoTime = StringToFloat(sArgs);
		}
		
		DeleteTimer(client);


		if (fIncognitoTime > 0)
		{
			g_hIncognitoTimer[client] = CreateTimer(fIncognitoTime, Timer_Incognito, GetClientUserId(client));
			CGOPrintToChat(client, "%s%T", g_sPrefix, "playertags_incognito_on", client, fIncognitoTime);
			g_bIncognitoForever[client] = false;
			SetClientCookie(client, g_hCookie, "0");
		}
		else
		{
			CGOPrintToChat(client, "%s%T", g_sPrefix, "playertags_incognito_on_perm", client, fIncognitoTime);
			g_bIncognitoForever[client] = true;
			SetClientCookie(client, g_hCookie, "1");
		}
	}

	LoadPlayerTags(client);

	HandleTag(client);

	return Plugin_Handled;
}

public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
	char sKey[64];

	if (!kv.GetSectionName(sKey, sizeof(sKey)))
		return Plugin_Continue;

	if (StrEqual(sKey, "ClanTagChanged"))
	{
		RequestFrame(Frame_HandleTag, GetClientUserId(client));
	}

	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client)
{
	CS_GetClientClanTag(client, g_sPlayerTag[client], sizeof(g_sPlayerTag[]));
	if(g_bIncognitoForever[client] == true)
	{
		if(ReadFlagString(g_sAdminFlag) & GetUserFlagBits(client))
			g_bIncognito[client] = true;
	}
	else if (g_bJoinIncognito)
	{
		if(ReadFlagString(g_sAdminFlag) & GetUserFlagBits(client))
		{
			g_bIncognito[client] = true;
			if (g_fIncognitoTime > 0)
				g_hIncognitoTimer[client] = CreateTimer(g_fIncognitoTime, Timer_Incognito, GetClientUserId(client));
		}
	}

	LoadPlayerTags(client);

	HandleTag(client);
}

public Action Timer_Incognito(Handle tmr, int userid)
{
	int client = GetClientOfUserId(userid);

	g_bIncognito[client] = false;

	LoadPlayerTags(client);

	HandleTag(client);

	CGOPrintToChat(client, "%s%T", g_sPrefix, "playertags_incognito_off", client);

	g_hIncognitoTimer[client] = null;

	return Plugin_Handled;
}

public void Event_CheckTag(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	HandleTag(client);
}

public void OnClientDisconnect(int client)
{
	DeleteTimer(client);
}

public void Frame_HandleTag(int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client)
		return;

	HandleTag(client);
}

void LoadPlayerTags(int client)
{
	KeyValues kvMenu = new KeyValues("PlayerTags");

	if (!kvMenu.ImportFromFile(CONFIG))
	{
		delete kvMenu;
		SetFailState("PlayerTags - Не найден файл %s ", CONFIG);
	}

	char steamid[24];
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid)))
	{
		LogError("Не удалось получить STEAMID %L", client);

		if (kvMenu.JumpToKey("default", false))
		{
			GetTags(client, kvMenu);

			delete kvMenu;
			return;
		}
	}

	if(g_bIncognito[client] && ReadFlagString(g_sAdminFlag) & GetUserFlagBits(client))
	{
		if (kvMenu.JumpToKey("default", false))
		{
			GetTags(client, kvMenu);

			delete kvMenu;
			return;
		}
	}

	if (kvMenu.JumpToKey(steamid, false))
	{
		GetTags(client, kvMenu);

		delete kvMenu;
		return;
	}

	steamid[6] = '0';

	if (kvMenu.JumpToKey(steamid, false))
	{
		GetTags(client, kvMenu);

		delete kvMenu;
		return;
	}
	
	static char sGroup[32];
	AdminId admin = GetUserAdmin(client);
	if (admin != INVALID_ADMIN_ID)
	{
		GroupId group = admin.GetGroup(0, sGroup, sizeof(sGroup));
		if (group != INVALID_GROUP_ID)
		{
			if(kvMenu.JumpToKey(sGroup))
			{
				GetTags(client, kvMenu);
				delete kvMenu;
				return;
			}
		}
	}

	char sFlags[21] = "abcdefghijklmnopqrstz";

	for (int i = sizeof(sFlags) - 1; i >= 0; i--)
	{
		char sFlag[1];
		sFlag[0] = sFlags[i];
		
		if (ReadFlagString(sFlag) & GetUserFlagBits(client))
		{
			if (kvMenu.JumpToKey(sFlag))
			{
				GetTags(client, kvMenu);

				delete kvMenu;
				return;
			}
		}
	}

	if (kvMenu.JumpToKey("default", false))
	{
		GetTags(client, kvMenu);
	}

	delete kvMenu;
}

void GetTags(int client, KeyValues kvMenu)
{
	kvMenu.GetString("spectator", g_sStatsTag[client].SPECTATOR, sizeof(Roles::SPECTATOR), "");
	kvMenu.GetString("ct", g_sStatsTag[client].CT_TEAM, sizeof(Roles::CT_TEAM), "");
	kvMenu.GetString("t", g_sStatsTag[client].T_TEAM, sizeof(Roles::T_TEAM), "");
	kvMenu.GetString("spectator_chat", g_sChatTag[client].SPECTATOR, sizeof(Roles::SPECTATOR), "");
	kvMenu.GetString("ct_chat", g_sChatTag[client].CT_TEAM, sizeof(Roles::CT_TEAM), "");
	kvMenu.GetString("t_chat", g_sChatTag[client].T_TEAM, sizeof(Roles::T_TEAM), "");
	kvMenu.GetString("dead_chat", g_sChatTag[client].DEAD, sizeof(Roles::DEAD), "");
	kvMenu.GetString("ct_msg", g_sChatTag[client].CT_MSG, sizeof(Roles::CT_MSG), "{DEFAULT}");
	kvMenu.GetString("t_msg", g_sChatTag[client].T_MSG, sizeof(Roles::T_MSG), "{DEFAULT}");
	kvMenu.GetString("s_msg", g_sChatTag[client].S_MSG, sizeof(Roles::S_MSG), "{DEFAULT}");
}

void HandleTag(int client)
{
	if (!g_bStats || !IsValidClient(client, true, true))
		return;

	int team = GetClientTeam(client);
	if(!team)
		return;

	char buffer[TAG_LENGTH];
	switch(team)	
	{
		case CS_TEAM_T:
		{
			if(g_bNoOverwrite && strlen(g_sStatsTag[client].T_TEAM) < 1)
				FormatEx(buffer, sizeof(buffer), g_sPlayerTag[client]);
			else FormatEx(buffer, sizeof(buffer), g_sStatsTag[client].T_TEAM);
		}
		case CS_TEAM_CT:
		{
			if(g_bNoOverwrite && strlen(g_sStatsTag[client].CT_TEAM) < 1)
				FormatEx(buffer, sizeof(buffer), g_sPlayerTag[client]);
			else FormatEx(buffer, sizeof(buffer), g_sStatsTag[client].CT_TEAM);
		}
		case CS_TEAM_SPECTATOR:
		{
			if(g_bNoOverwrite && strlen(g_sStatsTag[client].SPECTATOR) < 1)
				FormatEx(buffer, sizeof(buffer), g_sPlayerTag[client]);
			else FormatEx(buffer, sizeof(buffer), g_sStatsTag[client].SPECTATOR);
		}
	}

	CS_SetClientClanTag(client, buffer);
}

void ReplaceStringColors(char[] sMessage, int iMaxLen)
{
	ReplaceString(sMessage, iMaxLen, "{DEFAULT}",		"\x01", false);
	ReplaceString(sMessage, iMaxLen, "{TEAM}",			"\x03", false);
	ReplaceString(sMessage, iMaxLen, "{GREEN}",			"\x04", false);
	ReplaceString(sMessage, iMaxLen, "{RED}",			"\x02", false);
	ReplaceString(sMessage, iMaxLen, "{LIME}",			"\x05", false);
	ReplaceString(sMessage, iMaxLen, "{LIGHTGREEN}",	"\x06", false);
	ReplaceString(sMessage, iMaxLen, "{LIGHTRED}",		"\x07", false);
	ReplaceString(sMessage, iMaxLen, "{GRAY}",			"\x08", false);
	ReplaceString(sMessage, iMaxLen, "{LIGHTOLIVE}",	"\x09", false);
	ReplaceString(sMessage, iMaxLen, "{OLIVE}",			"\x10", false);
	ReplaceString(sMessage, iMaxLen, "{PURPLE}",		"\x0E", false);
	ReplaceString(sMessage, iMaxLen, "{LIGHTBLUE}",		"\x0B", false);
	ReplaceString(sMessage, iMaxLen, "{BLUE}",			"\x0C", false);
}

public Action OnChatMessage(int &client, Handle recipients, char[] name, char[] message)
{
	if(!g_bChat)
		return Plugin_Continue;

	char sMsg[MAXLENGTH_MESSAGE];
	int team = GetClientTeam(client);
	switch(team)	
	{
		case CS_TEAM_T:
		{
			Format(name, MAXLENGTH_NAME, "%s %s", g_sChatTag[client].T_TEAM, name);
			FormatEx(sMsg, sizeof(sMsg), "%s", g_sChatTag[client].T_MSG);
		}
		case CS_TEAM_CT:
		{
			Format(name, MAXLENGTH_NAME, "%s %s", g_sChatTag[client].CT_TEAM, name);
			FormatEx(sMsg, sizeof(sMsg), "%s", g_sChatTag[client].CT_MSG);
		}
		case CS_TEAM_SPECTATOR:
		{
			Format(name, MAXLENGTH_NAME, "%s %s", g_sChatTag[client].SPECTATOR, name);
			FormatEx(sMsg, sizeof(sMsg), "%s", g_sChatTag[client].S_MSG);
		}
	}

	if(team != CS_TEAM_SPECTATOR && !IsPlayerAlive(client))
		Format(name, MAXLENGTH_NAME, "%s%s", g_sChatTag[client].DEAD, name);
	
	Format(name, MAXLENGTH_NAME, " %s", name);
	ReplaceStringColors(name, MAXLENGTH_NAME);
	ReplaceStringColors(sMsg, MAXLENGTH_NAME);
	Format(message, MAXLENGTH_MESSAGE, "%s%s", sMsg, message);

	return Plugin_Changed;
}

stock void DeleteTimer(int client)
{
	if(g_hIncognitoTimer[client])
	{
		CloseHandle(g_hIncognitoTimer[client]);
		g_hIncognitoTimer[client] = null;
	}
}

stock bool IsValidClient(int client, bool bots = true, bool dead = true)
{
	if (client <= 0)
		return false;

	if (client > MaxClients)
		return false;

	if (!IsClientInGame(client))
		return false;

	if (IsFakeClient(client) && !bots)
		return false;

	if (IsClientSourceTV(client))
		return false;

	if (IsClientReplay(client))
		return false;

	if (!IsPlayerAlive(client) && !dead)
		return false;

	return true;
}