#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "good_live"
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <store>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Store - Coupons",
	author = PLUGIN_AUTHOR,
	description = "Allows players to redeem Coupons",
	version = PLUGIN_VERSION,
	url = "painlessgaming.eu"
};

Database g_hDatabase;

Handle g_hTimer[MAXPLAYERS + 1] =  { null, ... };

ConVar g_cCooldown;

bool g_bConnected = false;

public void OnPluginStart()
{
	g_cCooldown = CreateConVar("store_coupons_cooldown", "5.0", "The command cooldown");
	
	RegConsoleCmd("sm_redeem", Command_Redeem);
	
	DB_Connect();
	
	AutoExecConfig(true);
	LoadTranslations("store_coupons.phrases");
}

public Action Command_Redeem(int client, int args)
{
	if(g_hTimer[client] != null)
	{
		CReplyToCommand(client, "%t %t", "TAG", "You have to wait till you can use this command");
		return Plugin_Handled;
	}
	
	if(args < 1)
	{
		CReplyToCommand(client, "%t %t", "TAG", "You have to provide a code");
		return Plugin_Handled;
	}
	
	g_hTimer[client] = CreateTimer(g_cCooldown.FloatValue, Timer_Cooldown, client);
	
	char sArg[32];
	GetCmdArg(1, sArg, sizeof(sArg));
	DB_CheckCode(client, sArg);

	return Plugin_Handled;
}

public Action Timer_Cooldown(Handle timer, int client)
{
	g_hTimer[client] = null;
	return Plugin_Stop;
}

public void OnClientPostAdminCheck(int client)
{
	if(g_hTimer[client] != null)
		KillTimer(g_hTimer[client]);
}

void DB_Connect() 
{
	if (SQL_CheckConfig("giftcode"))
	{
		Database.Connect(DB_Connected, "giftcode");
	} else {
		SetFailState("Couldn't find a 'giftcode' entry in your database.cfg. Please add it!");
	}
}

public void DB_Connected(Database db, const char[] er, any data)
{
	if(db == null || strlen(er) > 0){
		SetFailState("Database connection failed!: %s", er);
		return;
	}
	
	g_bConnected = true;
	
	g_hDatabase = db;
}

void DB_CheckCode(int client, char[] sCode)
{
	if(!g_bConnected)
	{
		CPrintToChat(client, "The Database is not connected yet. Please try it again later");
		return;
	}
	
	int userid = GetClientUserId(client);
	char sQuery[512];
	Format(sQuery, sizeof(sQuery), "SELECT value, code FROM codes WHERE code = '%s'", sCode);
	char sQueryES[sizeof(sQuery) * 2 + 1];
	g_hDatabase.Escape(sQuery, sQueryES, sizeof(sQueryES));
	g_hDatabase.Query(DB_CodeSelect, sQuery, userid);
}

public void DB_CodeSelect(Database db, DBResultSet results, const char[] error, int userid)
{
	int client = GetClientOfUserId(userid);
	if(!IsValidClient(client))
		return;
	if(db == null || strlen(error) > 0){
		LogError("Error during selecting a code: %s", error);
		CPrintToChat(client, "%t %t", "TAG", "An error occured. Please contact an admin");
		return;
	}
	
	if(results.FetchRow())
	{
		int value = results.FetchInt(0);
		CPrintToChat(client, "%t %t", "TAG", "You succesfully redeemed a code", value);
		Store_SetClientCredits(client, Store_GetClientCredits(client) + value);
		
		char sCode[32];
		results.FetchString(1, sCode, sizeof(sCode));
		char sQuery[512];
		Format(sQuery, sizeof(sQuery), "DELETE FROM codes WHERE code = '%s'", sCode);
		char sQueryES[sizeof(sQuery) * 2 + 1];
		g_hDatabase.Escape(sQuery, sQueryES, sizeof(sQueryES));
		g_hDatabase.Query(DB_CodeDeletion, sQuery, userid);
		
		char Path[526];
		BuildPath(Path_SM, Path, sizeof(Path), "logs/store_coupons.txt");
		LogToFile(Path, "%L redeemed a giftcode worth: %d credits. (%s)", client, value, sCode);
		
	}else{
		CPrintToChat(client, "%t %t", "TAG", "The provided code is invalid");
	}
}

public void DB_CodeDeletion(Database db, DBResultSet results, const char[] error, int userid)
{
	int client = GetClientOfUserId(userid);
	if(!IsValidClient(client))
		return;
	if(db == null || strlen(error) > 0){
		LogError("Failed to delete a code: %s", error);
		CPrintToChat(client, "%t %t", "TAG", "An error occured. Please contact an admin");
		return;
	}
}

stock bool IsValidClient(int client)
{
	if(0 > client  || client > MaxClients || !IsClientConnected(client))
		return false;
	return true;
}