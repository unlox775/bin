<?php

/**
 * PhoneySavePoint - An object-oriented PostgreSQL savepoint system (because PDO doesn't support nested savepoints!)
 *
 * Ok, actually it's not really doing it, but it does provide a
 * Very useful additional purpose until we get savepoints really
 * working: When you are in a generic method, such as a SimpleORM
 * object's method and you are doing something with several steps
 * in it, you don't know if your caller has already started a
 * transaction, but you want to make SURE that you are really in
 * a transaction so that of the steps of your process gets
 * committed without all of them being commited.
 *
 * Here's a quick usage example:
 * 
 * <code> 
 * ###  About to start doing serious stuff...
 * $savepoint = dbh_begin_savepoint();
 * 
 * ###  Change one: edit the student
 * $this->student->set_and_save(array('something' => "doesn't matter"));
 * ###  Change two: edit ourselves
 * try {
 *     $this->set_and_save(array('something_else' => "really don't matter"));
 * } catch (Exception $e) {
 *     $savepoint->rollback; # would have happened anyways when $savepoint fell out of scope
 * }
 *
 * ###  All done, we surrender the changes of this savepoint to the parent transaction
 * $savepoint->commit();
 * </code>
 *
 * In general it's probably always safer (and neater) to use this
 * class instead of PDO's beginTransaction() method.  Even
 * controllers can call other controllers, and PDO's
 * beginTransaction has NO way of knowing whether a transaction
 * has been started or not.  This will always be safe.
 */
$PhoneySavePoint_i = 1;
class PhoneySavePoint {
    public $started_trans = true;
    public $savepoint_id = null;
    public $closed = false;
    public $dbh = null;
    public function __construct($the_dbh = null) {
        global $dbh, $PhoneySavePoint_i;
        if (! is_null($the_dbh)) $this->dbh =& $the_dbh;
        else                     $this->dbh =& $dbh;
        try {
            $this->started_trans = $this->dbh->beginTransaction();
        } catch (PDOException $e) {
            $this->started_trans = false;
            $this->savepoint_id = 'phoney'.$PhoneySavePoint_i++;
            $this->dbh->exec("SAVEPOINT ". $this->savepoint_id);
        }
    }
    public function commit()   { if (! $this->closed) { if ($this->started_trans) $this->dbh->commit();    else $this->dbh->exec("RELEASE SAVEPOINT ".     $this->savepoint_id);  $this->closed = true;  return true; } else { return false; } }
    public function rollBack() { if (! $this->closed) { if ($this->started_trans) $this->dbh->rollBack();  else $this->dbh->exec("ROLLBACK TO SAVEPOINT ". $this->savepoint_id);  $this->closed = true;  return true; } else { return false; } }
    public function __destruct() { if (! $this->closed) $this->rollBack(); }
}
/**
 * dbh_begin_savepoint() - Get a new {@link PhoneySavePoint}
 * @return PhoneySavePoint
 */
function dbh_begin_savepoint() {
    global $dbh;
    return new PhoneySavePoint($dbh);
}
