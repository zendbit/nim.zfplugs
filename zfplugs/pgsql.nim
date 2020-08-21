#[
  zfcore web framework for nim language
  This framework if free to use and to modify
  License: BSD
  Author: Amru Rosyada
  Email: amru.rosyada@gmail.com
  Git: https://github.com/zendbit
]#

import db_postgres, strformat, json

import dbs, settings

type
  DbInfo* = tuple[username: string, password: string, database: string, host: string, port: int]
  PgSql* = ref object
    connId: string
    dbInfo: DbInfo
    conn: DbConn

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
proc newPgSql*(connId: string): PgSql =
  let jsonSettings = jsonSettings()
  if not jsonSettings.isNil:
    let db = jsonSettings{"database"}
    if not db.isNil:
      let dbConf = db{connId}
      if not dbConf.isNil:
        result = PgSql(connId: connId)
        result.dbInfo = (
          dbConf{"database"}.getStr(),
          dbConf{"username"}.getStr(),
          dbConf{"password"}.getStr(),
          dbConf{"host"}.getStr(),
          dbConf{"port"}.getInt())
        let c = newDbs(
          result.dbInfo.database,
          result.dbInfo.username,
          result.dbInfo.password,
          result.dbInfo.host,
          result.dbInfo.port).tryPgSqlConn()

        if c.success:
          result.conn = c.conn
        else:
          echo c.msg

      else:
        echo &"database {connId} not found!!."

    else:
      echo "database section not found!!."

proc getDbInfo*(pgSqlDb: PgSql): DbInfo =
  return pgSqlDb.dbInfo

# test ping the server
proc ping*(conn: DbConn): bool =
  try:
    conn.exec(sql "SELECT 1")
    result = true
  except:
    discard

# get connId
proc connId*(self: PgSql): string =
  if not self.isNil:
    result = self.connId

# get dbconn
proc conn*(self: PgSql): DbConn =
  if not self.isNil:
    result = self.conn

export
  db_postgres
