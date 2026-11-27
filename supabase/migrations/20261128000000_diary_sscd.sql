-- Phoenix: diary session types for social service (SSCD) and ceremonial
-- duties (Guard of Honour, band), which make up much of a unit's year.
alter type session_type add value if not exists 'sscd';
alter type session_type add value if not exists 'ceremonial';
