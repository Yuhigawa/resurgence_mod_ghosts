// Parachute infil — the battle royale drop-in.
//
// On spawn the player is lifted into the sky and descends slowly under
// control, steering with normal movement input, until they touch down. That
// is the Resurgence redeploy, and it also makes the opening of a match feel
// like a drop rather than a team deathmatch spawn.
//
// There is no parachute model or animation in Ghosts multiplayer, so the
// player falls in a falling pose. Accepted, same as the dive.
//
// Three pieces make it work:
//   setorigin         puts them up there
//   setvelocity       clamps the descent into a glide and adds steering
//   the _ttk hook     cancels the landing damage (see fall_immune below)

init()
{
	level thread watch_players();
}

watch_players()
{
	for (;;)
	{
		level waittill( "connected", var_0 );
		var_0 thread infil_watch();
	}
}

infil_watch()
{
	self endon( "disconnect" );

	for (;;)
	{
		self waittill( "spawned_player" );

		if ( !getdvarint( "scr_resurgence_infil_enabled" ) )
			continue;

		// Let the spawn settle before moving the player, or the engine's own
		// spawn placement fights the teleport.
		wait 0.15;

		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
			continue;

		self thread infil();
	}
}

infil()
{
	self endon( "disconnect" );
	self endon( "death" );

	var_0 = getdvarfloat( "scr_resurgence_infil_height" );

	// The ground we were standing on before being lifted. Altitude above it
	// decides when the chute opens -- no trace needed.
	var_1 = self.origin[2];

	self.rsg_infil = 1;
	self.rsg_chute = 0;
	self setorigin( self.origin + ( 0, 0, var_0 ) );
	self setvelocity( ( 0, 0, 0 ) );
	self iprintlnbold( "FREEFALL" );
	scripts\mp\_resurgence::rsg_log( "infil: " + self.name + " freefall from " + var_0 );

	wait 0.25;

	var_2 = "stand";
	var_8 = gettime();

	for (;;)
	{
		// Safety net. If anything ever leaves a player airborne indefinitely
		// again, cut them loose rather than stranding them in the sky.
		if ( gettime() - var_8 > getdvarfloat( "scr_resurgence_infil_timeout" ) * 1000 )
		{
			scripts\mp\_resurgence::rsg_log( "infil: " + self.name + " TIMED OUT airborne, releasing" );
			break;
		}

		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
			break;

		var_3 = self.origin[2] - var_1;

		// isonground() reports TRUE on the first iterations after setorigin --
		// the engine has not processed the teleport yet -- which exited this
		// loop instantly and logged a landing one second into a drop while
		// the player was still in the sky with nothing controlling them.
		// Require real airtime AND real altitude before believing it.
		// Only airtime matters here, not altitude. Requiring "near the ground
		// you started on" stranded anyone who drifted over a tall building
		// and landed on a roof -- observed: three bots stuck airborne, one
		// at altitude 984, rescued only by the timeout.
		if ( gettime() - var_8 > 1500 && self isonground() )
			break;

		// Chute opens automatically near the ground, or stays shut if the
		// player cut it.
		// Altitude OR elapsed time: over high ground the altitude test alone
		// can never fire, and the player would freefall into the floor.
		if ( !self.rsg_chute && ( var_3 < getdvarfloat( "scr_resurgence_infil_chute_alt" ) || gettime() - var_8 > getdvarfloat( "scr_resurgence_infil_chute_time" ) * 1000 ) )
			deploy_chute();

		// Crouch cuts the chute and returns to freefall -- the dive you use
		// to beat someone to the ground.
		var_4 = self getstance();

		if ( var_4 == "crouch" && var_2 != "crouch" && self.rsg_chute )
		{
			self.rsg_chute = 0;
			self iprintlnbold( "CHUTE CUT" );
			scripts\mp\_resurgence::rsg_log( "infil: " + self.name + " cut chute at " + int( var_3 ) );
		}

		var_2 = var_4;

		if ( self.rsg_chute )
			chute_physics();
		else
			freefall_physics();

		wait 0.05;
	}

	wait 0.5;
	self.rsg_infil = 0;
	self.rsg_chute = 0;
	scripts\mp\_resurgence::rsg_log( "infil: " + self.name + " landed after " + int( ( gettime() - var_8 ) / 1000 ) + "s at altitude " + int( self.origin[2] - var_1 ) );
}

deploy_chute()
{
	self.rsg_chute = 1;
	self iprintlnbold( "CHUTE DEPLOYED" );
}

// Freefall: you fall fast, and you steer by LOOKING. Pitching down converts
// the fall into a dive, which is how you cover ground quickly or race someone
// to a landing.
freefall_physics()
{
	var_0 = self getplayerangles();
	var_1 = anglestoforward( var_0 );
	var_2 = getdvarfloat( "scr_resurgence_infil_freefall" );
	var_3 = getdvarfloat( "scr_resurgence_infil_dive" );

	// var_1[2] is negative when looking down, POSITIVE when looking up -- and
	// without a clamp that produced upward velocity, so a player who looked
	// up simply flew and never landed. Observed: nearly a minute airborne on
	// a drop that should take twenty seconds. Descent is now always downward.
	var_4 = 0 - var_2 + var_1[2] * var_3;
	var_9 = 0 - getdvarfloat( "scr_resurgence_infil_min_descent" );

	if ( var_4 > var_9 )
		var_4 = var_9;

	var_5 = self getnormalizedmovement();
	var_6 = anglestoright( var_0 );
	var_7 = ( var_1[0] * var_5[0] + var_6[0] * var_5[1], var_1[1] * var_5[0] + var_6[1] * var_5[1], 0 );
	var_7 = vectornormalize( var_7 );
	var_8 = getdvarfloat( "scr_resurgence_infil_freefall_steer" );

	self setvelocity( ( var_7[0] * var_8, var_7[1] * var_8, var_4 ) );
}

// Chute: slow, controlled, glides.
chute_physics()
{
	var_0 = self getvelocity();
	var_1 = getdvarfloat( "scr_resurgence_infil_descent" );

	// Clamp both ways: never faster than the chute allows, and never upward.
	if ( var_0[2] < 0 - var_1 || var_0[2] > 0 - getdvarfloat( "scr_resurgence_infil_min_descent" ) )
		var_0 = ( var_0[0], var_0[1], 0 - var_1 );

	var_2 = self getnormalizedmovement();

	if ( abs( var_2[0] ) > 0.1 || abs( var_2[1] ) > 0.1 )
	{
		var_3 = self getplayerangles();
		var_4 = anglestoforward( var_3 );
		var_5 = anglestoright( var_3 );
		var_6 = ( var_4[0] * var_2[0] + var_5[0] * var_2[1], var_4[1] * var_2[0] + var_5[1] * var_2[1], 0 );
		var_6 = vectornormalize( var_6 );
		var_7 = getdvarfloat( "scr_resurgence_infil_steer" );
		var_0 = ( var_6[0] * var_7, var_6[1] * var_7, var_0[2] );
	}

	self setvelocity( var_0 );
}

// Consulted by _ttk: no landing from a deployment should ever hurt.
fall_immune( player )
{
	if ( !isdefined( player ) )
		return 0;

	if ( !isdefined( player.rsg_infil ) )
		return 0;

	return player.rsg_infil;
}
