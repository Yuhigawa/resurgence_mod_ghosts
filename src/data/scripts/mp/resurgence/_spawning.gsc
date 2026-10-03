// Spawning — where you redeploy.
//
// Returns one of the MAP'S OWN spawn structs, never a synthesised origin:
// spawnplayer feeds the result to _spawnlogic::finalizespawnpointchoice
// (_playerlogic.gsc:659) and getspawnorigin (:660), and picking a point that
// is not a real spawn struct risks dropping players into geometry.

install_callbacks()
{
	level.getspawnpoint = ::rsg_getspawnpoint;
}

// ADR-7 discipline: measure, do not assume. The free-for-all spawn classname
// is not verifiable from data/ -- the scripts that would prove it are
// compiled in a fastfile -- so probe the candidates once and log what each
// returns, rather than trusting a name.
probe_classnames()
{
	if ( isdefined( level.rsg.spawnclass ) )
		return;

	var_0 = [];
	var_0[0] = "mp_dm_spawn";
	var_0[1] = "mp_tdm_spawn";
	var_0[2] = "mp_tdm_spawn_axis_start";
	var_0[3] = "mp_tdm_spawn_allies_start";
	var_0[4] = "mp_dm_spawn_start";
	var_0[5] = "mp_global_intermission";

	foreach ( var_1 in var_0 )
	{
		var_2 = maps\mp\gametypes\_spawnlogic::getspawnpointarray( var_1 );
		var_3 = 0;

		if ( isdefined( var_2 ) )
			var_3 = var_2.size;

		scripts\mp\_resurgence::rsg_log( "spawnprobe: " + var_1 + " -> " + var_3 + " point(s)" );

		if ( var_3 > 0 && !isdefined( level.rsg.spawnclass ) )
		{
			level.rsg.spawnclass = var_1;
			level.rsg.spawncount = var_3;
		}
	}

	if ( isdefined( level.rsg.spawnclass ) )
		scripts\mp\_resurgence::rsg_log( "spawnprobe: using " + level.rsg.spawnclass + " (" + level.rsg.spawncount + " points)" );
	else
		scripts\mp\_resurgence::rsg_log( "spawnprobe: NO SPAWN POINTS FOUND for any candidate" );
}

rsg_getspawnpoint()
{
	probe_classnames();

	var_0 = spawn_candidates();

	if ( var_0.size == 0 )
	{
		scripts\mp\_resurgence::rsg_log( "getspawnpoint: no candidates at all, deferring to spawnlogic random" );
		return maps\mp\gametypes\_spawnlogic::getspawnpoint_random( var_0 );
	}

	var_1 = in_zone( var_0 );

	if ( var_1.size == 0 )
	{
		scripts\mp\_resurgence::rsg_log( "getspawnpoint: no in-ring candidates, using all " + var_0.size );
		var_1 = var_0;
	}

	var_2 = nearest_living_squadmate();

	if ( !isdefined( var_2 ) )
	{
		scripts\mp\_resurgence::rsg_log( "getspawnpoint: " + self.name + " no living squadmate, random of " + var_1.size );
		return maps\mp\gametypes\_spawnlogic::getspawnpoint_random( var_1 );
	}

	var_3 = closest_to_but_not_on( var_1, var_2.origin, level.rsg.spawnmindist );
	scripts\mp\_resurgence::rsg_log( "getspawnpoint: " + self.name + " near " + var_2.name + ", " + int( distance( var_3.origin, var_2.origin ) ) + " units, from " + var_1.size + " candidates" );
	return var_3;
}

spawn_candidates()
{
	if ( !isdefined( level.rsg.spawnclass ) )
		return [];

	var_0 = maps\mp\gametypes\_spawnlogic::getspawnpointarray( level.rsg.spawnclass );

	if ( !isdefined( var_0 ) )
		return [];

	return var_0;
}

// The ring may not exist yet (Task 9, or scr_resurgence_zone_enabled 0), in
// which case every candidate is in bounds.
in_zone( points )
{
	if ( !isdefined( level.rsg_center ) || !isdefined( level.rsg_radius ) )
		return points;

	var_0 = [];

	foreach ( var_1 in points )
	{
		if ( distance2d( var_1.origin, level.rsg_center ) <= level.rsg_radius )
			var_0[var_0.size] = var_1;
	}

	return var_0;
}

nearest_living_squadmate()
{
	if ( !isdefined( self.rsg_squad ) )
		return undefined;

	var_0 = undefined;
	var_1 = 0;

	foreach ( var_2 in scripts\mp\resurgence\_squads::squad_living_members( self.rsg_squad ) )
	{
		if ( var_2 == self )
			continue;

		var_3 = distancesquared( var_2.origin, self.origin );

		if ( !isdefined( var_0 ) || var_3 < var_1 )
		{
			var_0 = var_2;
			var_1 = var_3;
		}
	}

	return var_0;
}

// "Near your squadmate" must not mean "on top of your squadmate". The closest
// spawn struct to a living player is usually the one he is standing on, which
// gave spawns 0 units apart -- two partners stacked on one point, both killed
// by one grenade, and at risk of spawn collision. Take the closest candidate
// that is at least mindist away, and only fall back to the absolute closest if
// nothing qualifies.
closest_to_but_not_on( points, origin, mindist )
{
	var_0 = undefined;
	var_1 = 0;

	foreach ( var_2 in points )
	{
		var_3 = distance( var_2.origin, origin );

		if ( var_3 < mindist )
			continue;

		if ( !isdefined( var_0 ) || var_3 < var_1 )
		{
			var_0 = var_2;
			var_1 = var_3;
		}
	}

	if ( isdefined( var_0 ) )
		return var_0;

	scripts\mp\_resurgence::rsg_log( "getspawnpoint: no candidate >= " + mindist + " units, falling back to closest" );
	return closest_to( points, origin );
}

closest_to( points, origin )
{
	var_0 = points[0];
	var_1 = distancesquared( points[0].origin, origin );

	foreach ( var_2 in points )
	{
		var_3 = distancesquared( var_2.origin, origin );

		if ( var_3 < var_1 )
		{
			var_0 = var_2;
			var_1 = var_3;
		}
	}

	return var_0;
}
