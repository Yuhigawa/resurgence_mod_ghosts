// Movement tuning.
//
// g_speed is the only real speed dvar on this build (default 190) and it
// scales EVERYTHING proportionally, so it alone cannot raise sprint or slide
// by a different amount than the base.
//
// self.movespeedscaler is the field the game itself uses for speed modifiers
// (_damage.gsc:2084 drops it to 0.05 when stunned), and the engine fires
// sprint_begin, sprint_end and sprint_slide_begin. So the base comes from
// g_speed and sprint/slide get extra scalars layered on top.
//
// There is NO slide-speed dvar: bg_slideSpeed and every variant of it do not
// exist on this build. There is also no slide_end notify, so the slide boost
// is held for a fixed window and then released.

init()
{
	apply_scales();

	level thread watch_players();
	level thread watch_dvars();
}

apply_scales()
{
	level.rsg.speedscale = getdvarfloat( "scr_resurgence_speed_scale" );
	level.rsg.sprintscale = getdvarfloat( "scr_resurgence_sprint_scale" );

	// g_speed is an integer dvar, so the base lands on the nearest whole unit
	// rather than exactly on the requested percentage.
	var_0 = int( 190 * level.rsg.speedscale + 0.5 );
	setdvar( "g_speed", var_0 );

	// Sprint and slide already inherit the base increase, so only the
	// difference is applied on top.
	level.rsg.sprintextra = level.rsg.sprintscale / level.rsg.speedscale;

	scripts\mp\_resurgence::rsg_log( "movement: g_speed " + var_0 + " (x" + level.rsg.speedscale + "), sprint x" + level.rsg.sprintscale + ", slide x" + getdvarfloat( "scr_resurgence_slide_scale" ) );
}

// Re-read every second so everything can be tuned mid-session over rcon.
// Applied only on change, so this does not fight anything else writing g_speed.
watch_dvars()
{
	level endon( "game_ended" );

	for (;;)
	{
		wait 1;

		if ( getdvarfloat( "scr_resurgence_speed_scale" ) == level.rsg.speedscale && getdvarfloat( "scr_resurgence_sprint_scale" ) == level.rsg.sprintscale )
			continue;

		apply_scales();
	}
}

watch_players()
{
	for (;;)
	{
		level waittill( "connected", var_0 );
		var_0 thread sprint_begin_watch();
		var_0 thread sprint_end_watch();
		var_0 thread slide_watch();
		var_0 thread spawn_reset_watch();
	}
}

// Separate threads for begin and end rather than one paired wait: a player who
// dies mid-sprint never fires sprint_end, which would strand a paired loop
// holding the boosted scaler.
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

slide_watch()
{
	self endon( "disconnect" );

	for (;;)
	{
		self waittill( "sprint_slide_begin" );

		self.movespeedscaler = getdvarfloat( "scr_resurgence_slide_scale" ) / level.rsg.speedscale;
		wait(getdvarfloat( "scr_resurgence_slide_time" ));
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
