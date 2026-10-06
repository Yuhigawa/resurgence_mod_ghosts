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

// Melee never reaches the replaced callback_playerdamage -- measured: the
// kill log recorded a MOD_MELEE hit that the hook never saw. level.
// callbackplayerdamage is the other documented entry (aliens.gsc:52 assigns
// it), so claim that too and see whether melee arrives by this route.
install_callbacks()
{
	level.callbackplayerdamage = ::rsg_callback_playerdamage;
}

rsg_callback_playerdamage( var_0, var_1, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9 )
{
	var_10 = scaled_damage( var_1, var_2, var_4 );

	// Kept, dvar-gated: this probe is what revealed that melee travels a
	// different entry point, and it is the fastest way to answer any future
	// "why does X hit for Y" question.
	if ( getdvarint( "scr_resurgence_debug_damage", 0 ) )
		scripts\mp\_resurgence::rsg_log( "dmg: mod=" + var_4 + " in=" + var_2 + " out=" + var_10 + " hp=" + self.health + "/" + self.maxhealth + " weap=" + var_5 );

	var_2 = var_10;
	maps\mp\gametypes\_damage::callback_playerdamage_internal( var_0, var_1, self, var_2, var_3, var_4, var_5, var_6, var_7, var_8, var_9 );
}

// Read live from dvars so time-to-kill can be tuned mid-session over rcon
// without a restart.
scaled_damage( attacker, damage, mod )
{
	// Only player-dealt damage is scaled. Ring damage, falling and world
	// damage carry no player attacker and must keep their configured values,
	// or tuning gun damage would silently retune the gas as well.
	// A parachute landing must never hurt, and fall damage carries no player
	// attacker so it would otherwise pass through untouched.
	if ( mod == "MOD_FALLING" && scripts\mp\resurgence\_infil::fall_immune( self ) )
		return 0;

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
