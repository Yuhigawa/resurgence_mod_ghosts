// The shrinking ring.
//
// Centre and extent are derived from the map's own spawn points, so the mode
// needs no per-map configuration: put a different map in rotation and the
// ring re-centres itself.

init()
{
	if ( !getdvarint( "scr_resurgence_zone_enabled" ) )
	{
		scripts\mp\_resurgence::rsg_log( "zone: disabled" );
		return;
	}

	level thread run();
}

run()
{
	level endon( "game_ended" );

	level waittill( "prematch_over" );

	// _spawning fills level.rsg.spawnclass the first time a spawn point is
	// requested; if the ring starts before anyone has spawned, probe now.
	scripts\mp\resurgence\_spawning::probe_classnames();

	level.rsg_center = map_centroid();
	level.rsg_radius = getdvarfloat( "scr_resurgence_zone_radius_start" );

	var_0 = max( 1, getdvarint( "scr_resurgence_zone_phases" ) );
	var_1 = getdvarfloat( "scr_resurgence_zone_radius_start" );
	var_2 = getdvarfloat( "scr_resurgence_zone_radius_end" );
	var_3 = getdvarint( "scr_resurgence_zone_hold" );
	var_4 = getdvarint( "scr_resurgence_zone_shrink" );

	scripts\mp\_resurgence::rsg_log( "zone: center " + level.rsg_center + ", radius " + level.rsg_radius + ", " + var_0 + " phases" );
	markers_create();
	level thread damage_loop();

	for ( var_5 = 1; var_5 <= var_0; var_5++ )
	{
		wait(var_3);

		var_6 = var_1 - ( var_1 - var_2 ) * var_5 / var_0;
		iprintln( "RESURGENCE: the ring is closing" );
		scripts\mp\_resurgence::rsg_log( "zone: phase " + var_5 + "/" + var_0 + " shrinking " + int( level.rsg_radius ) + " -> " + int( var_6 ) );
		shrink_to( var_6, var_4 );
	}

	scripts\mp\_resurgence::rsg_log( "zone: final radius " + int( level.rsg_radius ) );
}

shrink_to( target, seconds )
{
	level endon( "game_ended" );

	var_0 = int( seconds * 10 );

	if ( var_0 < 1 )
		var_0 = 1;

	var_1 = level.rsg_radius;

	for ( var_2 = 1; var_2 <= var_0; var_2++ )
	{
		level.rsg_radius = var_1 + ( target - var_1 ) * var_2 / var_0;
		markers_update();
		wait 0.1;
	}

	level.rsg_radius = target;
	markers_update();
}

damage_loop()
{
	level endon( "game_ended" );

	var_0 = getdvarint( "scr_resurgence_zone_damage" );

	for (;;)
	{
		wait 1;

		if ( !isdefined( level.rsg_radius ) )
			continue;

		foreach ( var_1 in level.players )
		{
			if ( !scripts\mp\resurgence\_squads::rsg_is_alive( var_1 ) )
				continue;

			if ( distance2d( var_1.origin, level.rsg_center ) <= level.rsg_radius )
			{
				if ( isdefined( var_1.rsg_outside ) && var_1.rsg_outside )
					var_1.rsg_outside = 0;

				continue;
			}

			if ( !isdefined( var_1.rsg_outside ) || !var_1.rsg_outside )
			{
				var_1.rsg_outside = 1;
				var_1 iprintlnbold( "OUTSIDE THE RING - MOVE IN" );
				scripts\mp\_resurgence::rsg_log( "zone: " + var_1.name + " outside at " + int( distance2d( var_1.origin, level.rsg_center ) ) + " / " + int( level.rsg_radius ) );
			}

			// Two arguments only. The six-argument form that would let us
			// pass MOD_TRIGGER_HURT silently dealt NO damage -- players sat
			// outside a shrinking ring for 19s at 5/sec and never died --
			// so the attribution is sacrificed for damage that actually
			// lands. Cost: the log records ring damage as MOD_HEAD_SHOT,
			// which is cosmetic but will read oddly in the killfeed.
			var_1 dodamage( var_0, var_1.origin );
		}
	}
}

// The centroid of the map's spawn points, which is a good enough "middle of
// the playable area" without any per-map data.
map_centroid()
{
	var_0 = scripts\mp\resurgence\_spawning::spawn_candidates();

	if ( var_0.size == 0 )
	{
		scripts\mp\_resurgence::rsg_log( "zone: NO SPAWN POINTS, centring on origin" );
		return ( 0, 0, 0 );
	}

	var_1 = ( 0, 0, 0 );

	foreach ( var_2 in var_0 )
		var_1 = var_1 + var_2.origin;

	return var_1 / var_0.size;
}

// The ring drawn on the compass as a circle of objective markers.
//
// There is no engine primitive for "draw a circle on the minimap", so the
// circumference is approximated by N objective icons that are repositioned
// as the ring shrinks. Indices start high because gametypes use the low ones
// and nothing else in this build touches the objective API.
markers_create()
{
	level.rsg.markercount = getdvarint( "scr_resurgence_zone_markers" );

	if ( level.rsg.markercount <= 0 )
	{
		scripts\mp\_resurgence::rsg_log( "zone: markers disabled" );
		return;
	}

	for ( var_0 = 0; var_0 < level.rsg.markercount; var_0++ )
		objective_add( marker_index( var_0 ), "active", marker_origin( var_0 ) );

	scripts\mp\_resurgence::rsg_log( "zone: created " + level.rsg.markercount + " ring markers" );
}

markers_update()
{
	if ( !isdefined( level.rsg.markercount ) || level.rsg.markercount <= 0 )
		return;

	for ( var_0 = 0; var_0 < level.rsg.markercount; var_0++ )
		objective_position( marker_index( var_0 ), marker_origin( var_0 ) );
}

markers_delete()
{
	if ( !isdefined( level.rsg.markercount ) || level.rsg.markercount <= 0 )
		return;

	for ( var_0 = 0; var_0 < level.rsg.markercount; var_0++ )
		objective_delete( marker_index( var_0 ) );

	level.rsg.markercount = 0;
}

marker_index( n )
{
	return 40 + n;
}

marker_origin( n )
{
	var_0 = 360 / level.rsg.markercount * n;
	var_1 = level.rsg_center + ( cos( var_0 ) * level.rsg_radius, sin( var_0 ) * level.rsg_radius, 0 );
	return var_1;
}
