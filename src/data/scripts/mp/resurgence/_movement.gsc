// Movement tuning.
//
// g_speed is the only real speed dvar on this build (default 190) and it
// scales EVERYTHING proportionally -- walk, sprint, strafe -- so it alone
// cannot raise sprint by a different amount than the base.
//
// self.movespeedscaler is the field the game itself uses for speed modifiers
// (_damage.gsc:2084 drops it to 0.05 when stunned, _playerlogic.gsc:611
// restores it to 1), and the engine fires sprint_begin / sprint_end. So the
// base comes from g_speed and the extra sprint boost is a scalar applied only
// while sprinting.

init()
{
	level.rsg.speedscale = getdvarfloat( "scr_resurgence_speed_scale" );
	level.rsg.sprintscale = getdvarfloat( "scr_resurgence_sprint_scale" );

	// g_speed is an integer dvar, so the base lands on the nearest whole
	// unit rather than exactly on the requested percentage.
	var_0 = int( 190 * level.rsg.speedscale + 0.5 );
	setdvar( "g_speed", var_0 );

	// Sprint already inherits the base increase, so apply only the
	// difference on top of it.
	level.rsg.sprintextra = level.rsg.sprintscale / level.rsg.speedscale;

	scripts\mp\_resurgence::rsg_log( "movement: g_speed " + var_0 + " (x" + level.rsg.speedscale + "), sprint x" + level.rsg.sprintscale + " via scaler " + level.rsg.sprintextra );

	level thread watch_players();
	level thread watch_dvars();
}

// Both scales are re-read every second so they can be tuned mid-session over
// rcon without a restart. Only applied when they actually change, so this
// does not fight anything else that writes g_speed.
watch_dvars()
{
	level endon( "game_ended" );

	for (;;)
	{
		wait 1;

		var_0 = getdvarfloat( "scr_resurgence_speed_scale" );
		var_1 = getdvarfloat( "scr_resurgence_sprint_scale" );

		if ( var_0 == level.rsg.speedscale && var_1 == level.rsg.sprintscale )
			continue;

		level.rsg.speedscale = var_0;
		level.rsg.sprintscale = var_1;
		level.rsg.sprintextra = var_1 / var_0;

		var_2 = int( 190 * var_0 + 0.5 );
		setdvar( "g_speed", var_2 );
		scripts\mp\_resurgence::rsg_log( "movement: retuned live -- g_speed " + var_2 + " (x" + var_0 + "), sprint x" + var_1 );
	}
}

watch_players()
{
	for (;;)
	{
		level waittill( "connected", var_0 );
		var_0 thread sprint_begin_watch();
		var_0 thread sprint_end_watch();
		var_0 thread spawn_reset_watch();
	}
}

// Separate threads for begin and end rather than one paired wait: a player
// who dies mid-sprint never fires sprint_end, which would strand a paired
// loop holding the boosted scaler.
sprint_begin_watch()
{
	self endon( "disconnect" );

	for (;;)
	{
		self waittill( "sprint_begin" );
		self.movespeedscaler = level.rsg.sprintextra;
	}
}

sprint_end_watch()
{
	self endon( "disconnect" );

	for (;;)
	{
		self waittill( "sprint_end" );
		self.movespeedscaler = 1;
	}
}

spawn_reset_watch()
{
	self endon( "disconnect" );

	for (;;)
	{
		self waittill( "spawned_player" );
		self.movespeedscaler = 1;
	}
}
