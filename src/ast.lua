local M = {}

M.types = {
    LUA_TABLE = 'lua:table',
    IDENT_NAME = 'ident:name',
    LUA_FN = 'lua:fn',
    ASSIGN = 'expr:assign',
    ARG_LIST = 'expr:arglist',
    RAW_WORD = 'raw:word',
    EXPORT = 'decl:export',
}


return M