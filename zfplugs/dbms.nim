#[
  zfcore web framework for nim language
  This framework if free to use and to modify
  License: BSD
  Author: Amru Rosyada
  Email: amru.rosyada@gmail.com
  Git: https://github.com/zendbit
]#

import strformat, strutils, sequtils, json, options, re, db_mysql, db_postgres, db_sqlite
import stdext. json_ext
import dbs, settings, dbssql
export dbs, dbssql

type
  DbInfo* = tuple[
    database: string,
    username: string,
    password: string,
    host: string, port: int]

  DBMS*[T] = ref object
    connId*: string
    dbInfo*: DbInfo
    conn*: T
    connected*: bool

  KVObj* = tuple[
    keys: seq[string],
    values: seq[string],
    nodesKind: seq[JsonNodeKind]]

  InsertIdResult* = tuple[
    ok: bool,
    insertId: int64,
    msg: string]

  UpdateResult* = tuple[
    ok: bool,
    affected: int64,
    msg: string]
  
  ExecResult* = tuple[
    ok: bool,
    msg: string]

  RowResult*[T] = tuple[
    ok: bool,
    row: T,
    msg: string]

  RowsResult*[T] = tuple[
    ok: bool,
    rows: seq[T],
    msg: string]

  AffectedRowsResult* = tuple[
    ok: bool,
    affected: int64,
    msg: string]

#var db: DBConn

#
# this will read the settings.json on the section
# "database": {
#   "your_connId_setting": {
#     "username": "",
#     "password": "",
#     "database": "",
#     "host": "",
#     "port": 1234
#   }
# }
#
proc newDBMS*[T](connId: string): DBMS[T] {.gcsafe.} =
  let jsonSettings = jsonSettings()
  if not jsonSettings.isNil:
    let db = jsonSettings{"database"}
    if not db.isNil:
      let dbConf = db{connId}
      if not dbConf.isNil:
        result = DBMS[T](connId: connId)
        result.dbInfo = (
          dbConf{"database"}.getStr(),
          dbConf{"username"}.getStr(),
          dbConf{"password"}.getStr(),
          dbConf{"host"}.getStr(),
          dbConf{"port"}.getInt())
        let c = newDbs[T](
          result.dbInfo.database,
          result.dbInfo.username,
          result.dbInfo.password,
          result.dbInfo.host,
          result.dbInfo.port).tryConnect()

        result.connected = c.success
        if c.success:
          result.conn = c.conn
        else:
          echo c.msg

      else:
        echo &"database {connId} not found!!."

    else:
      echo "database section not found!!."

proc tryConnect*[T](self: DBMS[T]): bool {.gcsafe.} =
  ##
  ## Try connect to database
  ## Generic T is type of MySql, PgSql, SqLite
  ##

  let c = newDbs[T](
    self.dbInfo.database,
    self.dbInfo.username,
    self.dbInfo.password,
    self.dbInfo.host,
    self.dbInfo.port).tryConnect()
  self.conn = c.conn
  self.connected = c.success
  result = self.connected

proc quote(str: string): string =
  result = (fmt"{str}")
    .replace(fmt"\", fmt"\\")
    .replace(fmt"'", fmt"\'")
    .replace(fmt""""""", fmt"""\"""")
    .replace(fmt"\x1a", fmt"\\Z")

proc extractKeyValue*[T](
  self: DBMS,
  obj: T): KVObj {.gcsafe.} =
  var keys: seq[string] = @[]
  var values: seq[string] = @[]
  var nodesKind: seq[JsonNodeKind] = @[]
  let obj = %obj
  for k, v in obj.discardNull:
    if k.toLower.contains("-as-"): continue
    
    var skip = false
    for kf in obj.keys:
      if kf.toLower.endsWith(&"as-{k}"):
        skip = true
        break
    if skip: continue

    keys.add(k)
    nodesKind.add(v.kind)
    if v.kind != JString:
      values.add($v)
    else:
      values.add(v.getStr)

  result = (keys, values, nodesKind)

proc quote(q: Sql): string =
  let q = q.toQs
  var queries = q.query.split("?")
  for i in 0..q.params.high:
    let p = q.params[i]
    let v = if p.nodeKind == JString: &"'{quote(p.val)}'" else: p.val
    queries.insert([v], (i*2) + 1)

  result = queries.join("")

# insert into database
proc insertId*[T](
  self: DBMS,
  table: string,
  obj: T): InsertIdResult {.gcsafe.} =
  
  var q = Sql()
  try:
    if not self.connected:
      result = (false, 0'i64, "can't connect to the database.")
    else:
      let kv = self.extractKeyValue(obj)
      var fieldItems: seq[FieldItem] = @[]
      for i in 0..kv.keys.high:
        fieldItems.add((kv.values[i], kv.nodesKind[i]))

      q = Sql()
        .insert(table, kv.keys)
        .value(fieldItems)
      
      result = (true,
        self.conn.insertId(sql quote(q)),
        "ok")

  except Exception as ex:
    echo &"{ex.msg}, {q.toQs}"
    echo quote(q)
    result = (false, 0'i64, ex.msg)

proc update*[T](
  self: DBMS,
  table: string,
  obj: T,
  query: Sql): UpdateResult {.gcsafe.} =
  ### update data table

  var q = Sql()
  try:
    if not self.connected:
      result = (false, 0'i64, "can't connect to the database.")
    else:
      let kv = self.extractKeyValue(obj)
      var fieldItems: seq[FieldItem] = @[]
      for i in 0..kv.keys.high:
        fieldItems.add((kv.values[i], kv.nodesKind[i]))
      
      q = Sql()
        .update(table, kv.keys)
        .value(fieldItems) & query
      
      result = (true,
        self.conn.execAffectedRows(sql quote(q)),
        "ok")

  except Exception as ex:
    echo &"{ex.msg}, {q.toQs}"
    echo quote(q)
    result = (false, 0'i64, ex.msg)

proc exec*(
  self: DBMS,
  query: Sql): ExecResult {.gcsafe.} =
  ###
  ### execute the query
  ###

  var q = Sql()
  try:
    if not self.connected:
      result = (false, "can't connect to the database.")
    else:
      q = query
      
      self.conn.exec(sql quote(q))
      result = (true, "ok")

  except Exception as ex:
    echo &"{ex.msg}, {q.toQs}"
    echo quote(q)
    result = (false, ex.msg)

proc extractFieldsAlias*(fields: seq[FieldDesc]): seq[FieldDesc] {.gcsafe.} =
  
  let fields = fields.map(proc (x: FieldDesc): FieldDesc =
    (x.name.replace("-as-", " AS ").replace("-AS-", " AS "), x.nodeKind))
  
  result = fields.filter(proc (x: FieldDesc): bool =
    result = true
    if not x.name.contains("AS "):
      for f in fields:
        if f.name.contains(&" AS {x.name}"):
          result = false
          break)

proc extractFieldsAlias*(fields: seq[FieldsPair]): seq[FieldsPair] {.gcsafe.} =
  
  let fields = fields.map(proc (x: FieldsPair): FieldsPair =
    (x.name.replace("-as-", " AS ").replace("-AS-", " AS "), x.val, x.nodeKind))
  
  result = fields.filter(proc (x: FieldsPair): bool =
    result = true
    if not x.name.contains("AS "):
      for f in fields:
        if f.name.contains(&" AS {x.name}"):
          result = false
          break)

proc normalizeFieldsAlias*(fields: seq[FieldDesc]): seq[FieldDesc] {.gcsafe.} =
  
  result = fields.extractFieldsAlias.map(proc (x: FieldDesc): FieldDesc =
    (x.name.split(" AS ")[0].strip, x.nodeKind))

proc normalizeFieldsAlias*(fields: seq[FieldsPair]): seq[FieldsPair] {.gcsafe.} =
  
  result = fields.extractFieldsAlias.map(proc (x: FieldsPair): FieldsPair=
    (x.name.split(" AS ")[0].strip, x.val, x.nodeKind))
    
proc extractQueryResults*(fields: seq[FieldDesc], queryResults: seq[string]): JsonNode {.gcsafe.} =
  
  result = %*{}
  if queryResults.len > 0 and queryResults[0] != "" and queryResults.len == fields.len:
    for i in 0..fields.high:
      for k, v in fields[i].name.toDbType(fields[i].nodeKind, queryResults[i]):
        var fprops = k.split(" AS ")
        result[fprops[fprops.high].strip] = v

proc getRow*[T](
  self: DBMS,
  table: string,
  obj: T,
  query: Sql): RowResult[T] {.gcsafe.} =

  var q = Sql()
  try:
    if not self.connected:
      result = (false, obj, "can't connect to the database.")
    else:
      let fields = extractFieldsAlias(obj.fieldsDesc)
      q = (Sql()
        .select(fields.map(proc(x: FieldDesc): string = x.name))
        .fromTable(table) & query)
       
      let queryResults = self.conn.getRow(sql quote(q))
      result = (true, extractQueryResults(fields, queryResults).to(T), "ok")
  except Exception as ex:
    echo &"{ex.msg}, {q.toQs}"
    echo quote(q)
    result = (false, obj, ex.msg)

proc getAllRows*[T](
  self: DBMS,
  table: string,
  obj: T,
  query: Sql): RowsResult[T] {.gcsafe.} =
  ###
  ### Retrieves a single row. If the query doesn't return any rows,
  ###

  var q = Sql()
  try:
    if not self.connected:
      result = (false, @[], "can't connect to the database.")
    else:
      let fields = extractFieldsAlias(obj.fieldsDesc)
      q = (Sql()
        .select(fields.map(proc(x: FieldDesc): string = x.name))
        .fromTable(table) & query)

      let queryResults = self.conn.getAllRows(sql quote(q))
      var res: seq[T] = @[]
      if queryResults.len > 0 and queryResults[0][0] != "":
        for qres in queryResults:
          res.add(extractQueryResults(fields, qres).to(T))
      result = (true, res, "ok")
  except Exception as ex:
    echo &"{ex.msg}, {q.toQs}"
    echo quote(q)
    result = (false, @[], ex.msg)

proc execAffectedRows*(
  self: DBMS,
  query: Sql): AffectedRowsResult {.gcsafe.} =
  ###
  ### runs the query (typically "UPDATE") and returns the number of affected rows
  ###

  var q = Sql()
  try:
    if not self.connected:
      result = (false, 0'i64, "can't connect to the database.")
    else:
      q = query

      result = (true, self.conn.execAffectedRows(sql quote(q)), "ok")
  except Exception as ex:
    echo &"{ex.msg}, {q.toQs}"
    echo quote(q)
    result = (false, 0'i64, ex.msg)

proc delete*[T](
  self: DBMS,
  table: string,
  obj: T,
  query: Sql): AffectedRowsResult {.gcsafe.} =
  ###
  ### runs the query delete and returns the number of affected rows
  ###
  
  var q = Sql()
  try:
    if not self.connected:
      result = (false, 0'i64, "can't connect to the database.")
    else:
      q = (Sql()
        .delete(table) & query)
      
      result = (true, self.conn.execAffectedRows(sql quote(q)), "ok")
  except Exception as ex:
    echo &"{ex.msg}, {q.toQs}"
    echo quote(q)
    result = (false, 0'i64, ex.msg)

proc setEncoding(
  self: DBMS,
  encoding: string): bool {.gcsafe.} =
  ###
  ### sets the encoding of a database connection, returns true for success, false for failure
  ###
  if not self.connected:
    result = false
  else:
    result = self.conn.setEncoding(encoding)

proc getDbInfo*(self: DBMS): DbInfo {.gcsafe.} =
  result = self.dbInfo

# close the database connection
proc close*(self: DBMS) {.gcsafe.} =
  try:
    self.conn.close
  except:
    discard
  self.connected = false

# test ping the server
proc ping*(self: DBMS): bool {.gcsafe.} =
  try:
    if not self.connected:
      result = self.connected
    else:
      discard self.conn.getRow(sql "SELECT 1")
      result = true
  except Exception as e:
    echo e.msg
    self.close
    discard

# get connId
proc connId*(self: DBMS): string {.gcsafe.} =
  if not self.isNil:
    result = self.connId

proc startTransaction*(self: DBMS): ExecResult {.gcsafe discardable.} =

  result = self.exec(Sql().startTransaction)

proc commitTransaction*(self: DBMS): ExecResult {.gcsafe discardable.} =

  result = self.exec(Sql().commitTransaction)

proc savePointTransaction*(
  self: DBMS,
  savePoint: string): ExecResult {.gcsafe discardable.} =

  result = self.exec(Sql().savePointTransaction(savePoint))

proc rollbackTransaction*(
  self: DBMS,
  savePoint: string = ""): ExecResult {.gcsafe discardable.} =

  result = self.exec(Sql().rollbackTransaction(savePoint))
  if result.ok:
    result = self.exec(Sql().commitTransaction)

proc toWhereQuery*(
  j: JsonNode,
  tablePrefix: string = "",
  op: string = "AND"): tuple[where: string, params: seq[FieldItem]] =

  var where: seq[string] = @[]
  let fp = j.fieldsPair.normalizeFieldsAlias
  var whereParams: seq[FieldItem] = @[]
  for (k, v, kind) in fp:
    if kind == JNull: continue
    where.add(if tablePrefix == "": &"{k}=?" else: &"{tablePrefix}.{k}=?")
    whereParams.add((v, kind))

  result = (where.join(&" {op} "), whereParams)

proc toWhereQuery*[T](
  obj: T,
  tablePrefix: string = "",
  op: string = "AND"): tuple[where: string, params: seq[FieldItem]] =

  result = (%obj).toWhereQuery(tablePrefix, op)

