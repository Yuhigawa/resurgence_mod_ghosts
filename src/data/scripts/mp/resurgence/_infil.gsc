// Parachute infil — the battle royale drop-in.
//
// Every spawn is a drop: freefall first, steered by looking, then a chute
// that opens near the ground and can be cut with crouch to dive again.
//
// No parachute model or animation exists in Ghosts multiplayer, so the player
// falls in a falling pose. Accepted deliberately.
//
// The hard-won rule here: a drop point must be in OPEN SKY with REAL GROUND
// beneath it. Two earlier versions failed on exactly this and left players
// frozen in mid-air until a timeout released them.

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

		// Unconditional, and BEFORE the enabled check. infil() carries
		// endon( "death" ), so dying mid-drop skips its own cleanup and
		// leaves rsg_infil set. A stale flag means fall_immune() returns
		// true forever, and _zone consults that for gas damage -- a
		// permanently gas-immune player cannot be killed by the ring, so
		// last-squad-standing never resolves and the match hangs with no
		// error anywhere.
		self.rsg_infil = 0;
		self.rsg_chute = 0;
		self.rsg_chute_cut = 0;

		if ( !getdvarint( "scr_resurgence_infil_enabled" ) )
			continue;

		// Let the engine's own spawn placement settle before moving anyone.
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

	var_0 = drop_point();

	if ( !isdefined( var_0 ) )
	{
		scripts\mp\_resurgence::rsg_log( "infil: " + self.name + " no valid drop point, skipping" );
		return;
	}

	var_1 = ground_below( var_0 );

	self.rsg_infil = 1;
	self.rsg_chute = 0;
	self.rsg_chute_cut = 0;
	self setorigin( var_0 );
	self setvelocity( ( 0, 0, 0 ) );
	self iprintlnbold( "FREEFALL" );
	scripts\mp\_resurgence::rsg_log( "infil: " + self.name + " freefall from altitude " + int( var_0[2] - var_1 ) );

	wait 0.25;

	var_2 = "stand";
	var_3 = gettime();

	for (;;)
	{
		// Safety net only. If this fires, the drop is broken -- it is not a
		// fix, it is a symptom, and the log should be read.
		if ( gettime() - var_3 > getdvarfloat( "scr_resurgence_infil_timeout" ) * 1000 )
		{
			scripts\mp\_resurgence::rsg_log( "infil: " + self.name + " TIMED OUT airborne at altitude " + int( self.origin[2] - var_1 ) + " -- DROP IS BROKEN" );
			break;
		}

		if ( !scripts\mp\resurgence\_squads::rsg_is_alive( self ) )
			break;

		var_4 = self.origin[2] - var_1;

		// Airtime plus ground contact. Altitude is deliberately NOT part of
		// this: requiring proximity to the starting ground stranded anyone
		// who landed on a roof.
		if ( gettime() - var_3 > 1500 && self isonground() )
			break;

		// Chute on altitude OR elapsed time, because over high ground the
		// altitude test alone may never fire.
		//
		// rsg_chute_cut is what makes cutting possible at all. Without it the
		// altitude test re-opened the chute 50ms after every cut, so cutting
		// did nothing anywhere below chute_alt -- which is the entire band
		// where a chute exists.
		if ( !self.rsg_chute && !self.rsg_chute_cut && ( var_4 < getdvarfloat( "scr_resurgence_infil_chute_alt" ) || gettime() - var_3 > getdvarfloat( "scr_resurgence_infil_chute_time" ) * 1000 ) )
			deploy_chute();

		// Crouch cuts the chute and returns to freefall.
		var_5 = self getstance();

		if ( var_5 == "crouch" && var_2 != "crouch" && self.rsg_chute )
		{
			self.rsg_chute = 0;
			self.rsg_chute_cut = 1;
			self iprintlnbold( "CHUTE CUT" );
		}

		var_2 = var_5;

		if ( self.rsg_chute )
			chute_physics();
		else
			freefall_physics();

		wait 0.05;
	}

	wait 0.5;
	self.rsg_infil = 0;
	self.rsg_chute = 0;
	scripts\mp\_resurgence::rsg_log( "infil: " + self.name + " landed after " + int( ( gettime() - var_3 ) / 1000 ) + "s at altitude " + int( self.origin[2] - var_1 ) );
}

deploy_chute()
{
	self.rsg_chute = 1;
	self iprintlnbold( "CHUTE DEPLOYED" );
}

// Freefall: fast, and steered by LOOKING. Pitching down converts the fall
// into a dive. Descent is clamped downward -- without that, looking up
// produced upward thrust and players flew instead of falling.
freefall_physics()
{
	var_0 = self getplayerangles();
	var_1 = anglestoforward( var_0 );
	var_2 = getdvarfloat( "scr_resurgence_infil_freefall" );

	// Velocity follows where you LOOK, in three dimensions. Previously the
	// vertical came from pitch while the horizontal was a flat value from
	// stick input alone, so looking down bought time in the air and no
	// distance -- and with no input at all the horizontal was zero, dropping
	// you perfectly vertically however you were aimed. A real skydive trades
	// altitude for ground covered, which is what this does.
	var_3 = ( var_1[0] * var_2, var_1[1] * var_2, var_1[2] * var_2 );

	// Stick input still adjusts, relative to facing.
	var_4 = self getnormalizedmovement();

	if ( abs( var_4[0] ) > 0.1 || abs( var_4[1] ) > 0.1 )
	{
		var_5 = anglestoright( var_0 );
		var_6 = ( var_1[0] * var_4[0] + var_5[0] * var_4[1], var_1[1] * var_4[0] + var_5[1] * var_4[1], 0 );
		var_6 = vectornormalize( var_6 );
		var_7 = getdvarfloat( "scr_resurgence_infil_freefall_steer" );
		var_3 = ( var_3[0] + var_6[0] * var_7, var_3[1] + var_6[1] * var_7, var_3[2] );
	}

	// Always descending: looking up must never produce lift.
	var_8 = 0 - getdvarfloat( "scr_resurgence_infil_min_descent" );

	if ( var_3[2] > var_8 )
		var_3 = ( var_3[0], var_3[1], var_8 );

	self setvelocity( var_3 );
}

chute_physics()
{
	var_0 = self getvelocity();
	var_1 = getdvarfloat( "scr_resurgence_infil_descent" );

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

// Consulted by _ttk and _zone: a drop must never take fall or gas damage.
fall_immune( player )
{
	if ( !isdefined( player ) )
		return 0;

	if ( !isdefined( player.rsg_infil ) )
		return 0;

	return player.rsg_infil;
}

// A drop point must satisfy BOTH conditions, and each has bitten us:
//
//   ground beneath it   -- scattering freely around the map centre put points
//                          over the void on small maps, and players hung there
//   open sky above it   -- a fixed height above the tallest spawn pushed the
//                          point past the world ceiling on lonestar, and
//                          players hung there too
//
// So the height is TRACED rather than assumed: from a real spawn point
// upwards, stopping at whatever ceiling exists. Spawn points guarantee ground;
// the trace guarantees we stay inside the world. Several are sampled and the
// one with the most headroom wins, which also rejects indoor spawns (measured
// ceilings of 49 and 72 units on hashima).
drop_point()
{
	var_0 = scripts\mp\resurgence\_spawning::spawn_candidates();

	if ( var_0.size == 0 )
		return undefined;

	var_1 = getdvarfloat( "scr_resurgence_infil_height" );
	var_2 = getdvarfloat( "scr_resurgence_infil_spread" );
	var_3 = undefined;
	var_4 = 0;

	for ( var_5 = 0; var_5 < 8; var_5++ )
	{
		var_6 = var_0[randomint( var_0.size )];
		var_7 = ( var_6.origin[0] + randomfloatrange( 0 - var_2, var_2 ), var_6.origin[1] + randomfloatrange( 0 - var_2, var_2 ), var_6.origin[2] + 16 );

		// How high can a player-sized volume actually rise from here?
		var_8 = playerphysicstrace( var_7, ( var_7[0], var_7[1], var_7[2] + var_1 ) );
		var_9 = var_8[2] - var_7[2];

		if ( var_9 > var_4 )
		{
			var_4 = var_9;
			var_3 = var_8;
		}

		// Good enough, stop looking.
		if ( var_4 > var_1 * 0.8 )
			break;
	}

	if ( !isdefined( var_3 ) || var_4 < 400 )
	{
		scripts\mp\_resurgence::rsg_log( "infil: best headroom only " + int( var_4 ) + ", no drop" );
		return undefined;
	}

	// Back off slightly so we are never flush against the ceiling.
	scripts\mp\_resurgence::rsg_log( "infil: drop headroom " + int( var_4 ) );
	return ( var_3[0], var_3[1], var_3[2] - 32 );
}

ground_below( pos )
{
	var_0 = playerphysicstrace( pos, ( pos[0], pos[1], pos[2] - 20000 ) );
	return var_0[2];
}
