// Omnimovement, approximated.
//
// What this is NOT: real BO6 omnimovement. That needs animation sets Ghosts
// does not ship and movement states implemented in the executable. Nothing
// here creates a new way to move -- it changes how fast existing movement is,
// and adds a velocity impulse for the dive. Expect the animations to be
// wrong: you will strafe at sprint speed in a walk animation, and dive
// looking like a man falling over. That was accepted deliberately.
//
// Two parts:
//
//   Omnidirectional speed. Vanilla moves you slower sideways and slower still
//   backwards. Reading getnormalizedmovement() -- [0] forward/back, [1]
//   left/right, the same call aliens.gsc:684 uses -- lets those directions be
//   boosted back up to roughly forward pace, which is what omnidirectional
//   movement feels like in practice.
//
//   Dive. Jump while sprinting launches you forward and slightly up with
//   setvelocity, then drops you prone on landing.

init()
{
	level thread watch_players();
}

watch_players()
{
	for (;;)
	{
		level waittill( "connected", var_0 );
		var_0 thread omni_watch();
		var_0 thread dive_watch();
		var_0 thread omnislide_watch();
	}
}

// Runs at 20Hz. Cheap: two builtin reads and at most one field write.
omni_watch()
{
	self endon( "disconnect" );

	for (;;)
	{
		wait 0.05;

		if ( !getdvarint( "scr_resurgence_omni_enabled" ) )
			continue;

		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
			continue;

		// Leave the dive alone -- it sets its own scaler.
		if ( isdefined( self.rsg_diving ) && self.rsg_diving )
			continue;

		var_0 = self getnormalizedmovement();
		var_1 = abs( var_0[0] );
		var_2 = abs( var_0[1] );

		if ( var_1 < 0.1 && var_2 < 0.1 )
			continue;

		// Sideways or backwards: the directions vanilla penalises.
		if ( var_2 > 0.5 || var_0[0] < -0.5 )
			self.movespeedscaler = getdvarfloat( "scr_resurgence_omni_scale" ) / level.rsg.speedscale;
	}
}

dive_watch()
{
	self endon( "disconnect" );

	for (;;)
	{
		wait 0.05;

		if ( !getdvarint( "scr_resurgence_dive_enabled" ) )
			continue;

		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
			continue;

		if ( !self jumpbuttonpressed() )
			continue;

		// Dive replaces the sprint-jump, so it needs forward input to
		// trigger -- a standing jump stays a jump.
		var_0 = self getnormalizedmovement();

		if ( var_0[0] < 0.5 )
			continue;

		if ( !self isonground() )
			continue;

		dive();
	}
}

dive()
{
	self endon( "disconnect" );
	self endon( "death" );

	self.rsg_diving = 1;

	var_0 = anglestoforward( self getplayerangles() );
	var_1 = getdvarfloat( "scr_resurgence_dive_force" );
	var_2 = getdvarfloat( "scr_resurgence_dive_lift" );

	self setvelocity( self getvelocity() + ( var_0[0] * var_1, var_0[1] * var_1, var_2 ) );
	scripts\mp\_resurgence::rsg_log( "dive: " + self.name );

	// Hit the deck on the way down, which is the only part of a dive the
	// engine can actually render here.
	wait 0.35;

	if ( scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
		self setstance( "prone" );

	wait(getdvarfloat( "scr_resurgence_dive_cooldown" ));
	self.rsg_diving = 0;
}

// Omnidirectional slide.
//
// Vanilla's slide is a SPRINT-slide: it only exists going forward, because it
// is triggered by crouching while sprinting and you cannot sprint backwards.
// So sliding back or sideways is impossible in stock Ghosts.
//
// This fakes it. getstance() going from standing to crouched while you are
// moving at speed is read as "slide intent", and the push is applied along
// the direction you are actually holding -- getnormalizedmovement() combined
// with your view angles -- rather than along your facing.
//
// No animation exists for it, so you will look like a crouching man skating
// backwards. That was accepted.
omnislide_watch()
{
	self endon( "disconnect" );

	var_0 = "stand";

	for (;;)
	{
		wait 0.05;

		if ( !getdvarint( "scr_resurgence_omnislide_enabled" ) )
			continue;

		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
		{
			var_0 = "stand";
			continue;
		}

		var_1 = self getstance();

		if ( var_1 == var_0 )
			continue;

		var_2 = var_0;
		var_0 = var_1;

		// Only the moment of dropping into a crouch counts.
		if ( var_1 != "crouch" || var_2 == "prone" )
			continue;

		if ( isdefined( self.rsg_sliding ) && self.rsg_sliding )
			continue;

		// Crouch means "cut the chute" while airborne, not "slide".
		if ( isdefined( self.rsg_infil ) && self.rsg_infil )
			continue;

		if ( !self isonground() )
			continue;

		var_3 = self getnormalizedmovement();

		// Forward slides are the engine's own job -- do not fight them.
		if ( var_3[0] > 0.5 )
			continue;

		if ( abs( var_3[0] ) < 0.3 && abs( var_3[1] ) < 0.3 )
			continue;

		self thread omnislide( var_3 );
	}
}

omnislide( move )
{
	self endon( "disconnect" );
	self endon( "death" );

	self.rsg_sliding = 1;

	// Direction the player is HOLDING, not the way he is facing: forward
	// times the forward/back axis, plus right times the strafe axis.
	var_0 = self getplayerangles();
	var_1 = anglestoforward( var_0 );
	var_2 = anglestoright( var_0 );

	var_3 = ( var_1[0] * move[0] + var_2[0] * move[1], var_1[1] * move[0] + var_2[1] * move[1], 0 );
	var_3 = vectornormalize( var_3 );

	var_4 = getdvarfloat( "scr_resurgence_omnislide_force" );
	scripts\mp\_resurgence::rsg_log( "omnislide: " + self.name + " dir " + move[0] + "," + move[1] + " force " + var_4 );

	// A single setvelocity does almost nothing: the engine clamps crouched
	// movement speed and overwrites it on the very next frame, which is why
	// the push felt weak no matter how large the number was. Re-apply it
	// every frame for the duration instead, decaying to a stop, and lift the
	// speed cap with movespeedscaler while it runs.
	var_5 = getdvarfloat( "scr_resurgence_omnislide_time" );
	var_6 = int( var_5 / 0.05 );

	if ( var_6 < 1 )
		var_6 = 1;

	self.movespeedscaler = getdvarfloat( "scr_resurgence_omnislide_scale" ) / level.rsg.speedscale;

	for ( var_7 = 0; var_7 < var_6; var_7++ )
	{
		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
			break;

		// Linear decay from full force to zero across the window.
		var_8 = var_4 * ( 1 - var_7 / var_6 );
		var_9 = self getvelocity();
		self setvelocity( ( var_3[0] * var_8, var_3[1] * var_8, var_9[2] ) );
		wait 0.05;
	}

	self.movespeedscaler = 1;

	wait(getdvarfloat( "scr_resurgence_omnislide_cooldown" ));
	self.rsg_sliding = 0;
}
