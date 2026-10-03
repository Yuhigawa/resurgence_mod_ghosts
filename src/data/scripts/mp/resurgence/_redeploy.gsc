// Redeploy — may I respawn, and after how long.
//
// The rule: you redeploy while any squadmate is alive. When none is, your
// whole squad is out for good. A player sitting out the redeploy delay does
// NOT count as alive, so a squad can be wiped while one of its members is
// still counting down -- that pending redeploy is cancelled.

init()
{
	// Verified in the Task 2 spike: replacefunc patches this call even though
	// spawnclient() calls mayspawn() from within the same script file.
	replacefunc( maps\mp\gametypes\_playerlogic::mayspawn, ::rsg_mayspawn );
}

install_callbacks()
{
	level.onrespawndelay = ::rsg_respawndelay;
}

rsg_respawndelay()
{
	scripts\mp\_resurgence::rsg_log( "respawndelay: " + self.name + " squad " + self.rsg_squad + " -> " + level.rsg.redeploydelay + "s (squadmate alive: " + may_redeploy( self ) + ")" );
	return level.rsg.redeploydelay;
}

// Replaces _playerlogic::mayspawn. Returning 0 routes the player to
// spectator via spawnclient() (_playerlogic.gsc:122-155).
rsg_mayspawn()
{
	if ( isdefined( self.rsg_eliminated ) && self.rsg_eliminated )
	{
		scripts\mp\_resurgence::rsg_log( "mayspawn: " + self.name + " eliminated, denied" );
		return 0;
	}

	// Vanilla's checks, kept verbatim. Dead code while scr_dm_numlives is 0
	// and level.disablespawning is never set (ADR-2) -- the whole block is
	// gated at _playerlogic.gsc:82 -- but correct if numlives is ever enabled.
	if ( maps\mp\_utility::getgametypenumlives() || isdefined( level.disablespawning ) )
	{
		if ( isdefined( level.disablespawning ) && level.disablespawning )
			return 0;

		if ( isdefined( self.pers["teamKillPunish"] ) && self.pers["teamKillPunish"] )
			return 0;

		if ( self.pers["lives"] <= 0 && maps\mp\_utility::gamehasstarted() )
			return 0;
		else if ( maps\mp\_utility::gamehasstarted() )
		{
			if ( !level.ingraceperiod && !self.hasspawned && ( isdefined( level.allowlatecomers ) && !level.allowlatecomers ) )
			{
				if ( isdefined( self.siegelatecomer ) && !self.siegelatecomer )
					return 1;

				return 0;
			}
		}
	}

	return 1;
}

may_redeploy( player )
{
	if ( !isdefined( player ) || !isdefined( player.rsg_squad ) )
		return 0;

	return scripts\mp\resurgence\_squads::squad_living_members( player.rsg_squad ).size > 0;
}

// Permanent elimination. Cancels a redeploy already being waited out:
// waitandspawnclient() endons "end_respawn" (_playerlogic.gsc:169).
eliminate( player )
{
	if ( !isdefined( player ) || ( isdefined( player.rsg_eliminated ) && player.rsg_eliminated ) )
		return;

	player.rsg_eliminated = 1;
	player notify( "end_respawn" );
	player maps\mp\_utility::clearlowermessage( "spawn_info" );
	scripts\mp\_resurgence::rsg_log( "eliminate: " + player.name + " (squad " + player.rsg_squad + ")" );

	if ( player.sessionstate == "playing" )
		player thread maps\mp\gametypes\_playerlogic::spawnspectator( player.origin + ( 0, 0, 60 ), player.angles );
}
