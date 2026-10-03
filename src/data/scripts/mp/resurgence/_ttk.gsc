// Time to kill.
//
// _damage.gsc:2146 callback_playerdamage is a two-line wrapper that forwards
// to callback_playerdamage_internal. Replacing the wrapper lets us scale the
// damage on the way through and still call the internal ourselves -- which
// matters because replacefunc gives no way to call an original, so hooking
// the internal directly would mean reimplementing 500 lines of damage logic.
//
// Argument order is the stock one:
//   ( inflictor, attacker, damage, dflags, mod, weapon, point, dir, hitloc, offsettime )

init()
{
	replacefunc( maps\mp\gametypes\_damage::callback_playerdamage, ::rsg_callback_playerdamage );
}

rsg_callback_playerdamage( var_0, var_1, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9 )
{
	var_2 = scaled_damage( var_1, var_2, var_4 );
	maps\mp\gametypes\_damage::callback_playerdamage_internal( var_0, var_1, self, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9 );
}

// Read live from dvars so time-to-kill can be tuned mid-session over rcon
// without a restart.
scaled_damage( attacker, damage, mod )
{
	// Only player-dealt damage is scaled. Ring damage, falling and world
	// damage carry no player attacker and must keep their configured values,
	// or tuning gun damage would silently retune the gas as well.
	if ( !isdefined( attacker ) || !isplayer( attacker ) )
		return damage;

	if ( mod == "MOD_MELEE" )
	{
		var_0 = getdvarint( "scr_resurgence_knife_hits" );

		if ( var_0 < 1 )
			var_0 = 1;

		// +1 so the last hit actually finishes the job: 100/3 is 33.3, and
		// three 33s leaves a man standing on 1 health.
		return int( self.maxhealth / var_0 ) + 1;
	}

	return int( damage * getdvarfloat( "scr_resurgence_damage_scale" ) );
}
