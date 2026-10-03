// Friendly fire — squadmates cannot damage each other.
//
// Without this, duos are unplayable: in free-for-all every player is a valid
// target, so your partner is too.

init()
{
	// _damage.gsc:1602 funnels every friendly-fire decision through this one
	// predicate as var_13, so a single cross-script hook covers all damage
	// paths -- including those in stock files we cannot read. Cross-script
	// replacefunc was verified working in the Task 2 spike.
	replacefunc( maps\mp\_utility::attackerishittingteam, ::rsg_attackerishittingteam );
}

// Argument order follows the call site: attackerishittingteam( victim, attacker ).
//
// The stock body is unreadable, so the non-squadmate path reproduces the shape
// of the one visible analogue, _damage.gsc::isfriendlyfire (:20-37). That is
// safe here because we only run under dm, where level.teambased is 0 and the
// stock function therefore returns 0 for every pair anyway: the only behaviour
// this must preserve is "0 unless squadmates". Confirmed in the kill log --
// bots on the same nominal team damage each other freely under dm, so .team is
// cosmetic there. It is also why init() is only called when the mod is
// enabled; on a teamed gametype this replacement would be wrong.
rsg_attackerishittingteam( victim, attacker )
{
	if ( scripts\mp\resurgence\_squads::same_squad( attacker, victim ) )
	{
		scripts\mp\_resurgence::rsg_log( "friendlyfire: blocked " + attacker.name + " -> " + victim.name + " (squad " + victim.rsg_squad + ")" );
		return 1;
	}

	if ( !isdefined( level.teambased ) || !level.teambased )
		return 0;

	if ( !isdefined( attacker ) || !isdefined( victim ) )
		return 0;

	if ( !isplayer( attacker ) && !isdefined( attacker.team ) )
		return 0;

	if ( victim == attacker )
		return 0;

	return victim.team == attacker.team;
}
