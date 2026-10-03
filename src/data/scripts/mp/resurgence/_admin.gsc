// Admin actions, triggered by setting a dvar.
//
// There is no way to register a console command from GSC, so each action is a
// dvar the server watches and resets to 0 once it has acted. That makes every
// action reachable over rcon, including from a player's own console via
// "rcon <command>".

init()
{
	level thread watch();
}

watch()
{
	level endon( "game_ended" );

	for (;;)
	{
		wait 0.5;

		if ( getdvarint( "scr_resurgence_admin_killbots", 0 ) )
		{
			setdvar( "scr_resurgence_admin_killbots", 0 );
			kill_bots();
		}

		if ( getdvarint( "scr_resurgence_admin_killall", 0 ) )
		{
			setdvar( "scr_resurgence_admin_killall", 0 );
			kill_all();
		}

		if ( getdvarint( "scr_resurgence_admin_restart", 0 ) )
		{
			setdvar( "scr_resurgence_admin_restart", 0 );
			scripts\mp\_resurgence::rsg_log( "admin: restarting the match" );
			iprintlnbold( "MATCH RESTARTING" );
			wait 1;
			maps\mp\gametypes\_gamelogic::forceend();
		}
	}
}

// Kills every bot and leaves humans alone. With solo squads that wipes every
// other squad, so the last human standing wins and the match ends -- which is
// the quickest way to see an ending without playing a whole round.
kill_bots()
{
	var_0 = 0;

	foreach ( var_1 in level.players )
	{
		if ( !isdefined( var_1 ) || !isai( var_1 ) )
			continue;

		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( var_1 ) )
			continue;

		var_1 suicide();
		var_0++;
	}

	scripts\mp\_resurgence::rsg_log( "admin: killed " + var_0 + " bot(s)" );
}

kill_all()
{
	var_0 = 0;

	foreach ( var_1 in level.players )
	{
		if ( !isdefined( var_1 ) || !scripts\mp\resurgence\_squads::rsg_is_alive( var_1 ) )
			continue;

		var_1 suicide();
		var_0++;
	}

	scripts\mp\_resurgence::rsg_log( "admin: killed " + var_0 + " player(s)" );
}
