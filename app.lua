local template = require('template')
local json = require('json')
local router = require('router').new()
local gs = require('gitserver')
local kvs = require('kvstore')
local ft = require('filetree')
local bs = require('blobstore')
local docstore = require('docstore')
local apps = require('apps')
local _blobstash = require('_blobstash')

router:get('/', function(params)
  app.response:write(template.render('index.html', 'layout.html', { status = _blobstash.status() }))
end)

router:get('/apps', function(params)
  local apps = apps.apps()
  app.response:write(template.render('apps.html', 'layout.html', { apps = apps }))
end)

router:get('/kvstore', function(params)
  if app.request:args():get("key") ~= "" then
    local kv = kvs.key(app.request:args():get("key"), app.request:args():get("version"))
    app.response:write(template.render('kvstore.html', 'layout.html', { kv = kv }))
    return
  end
  local keys, cursor = kvs.keys(app.request:args():get("cursor"))
  app.response:write(template.render('kvstore.html', 'layout.html', { keys = keys, cursor = cursor }))
end)

router:get('/blobstore', function(params)
  local blobs, cursor = bs.blobs("")
  app.response:write(template.render('blobstore.html', 'layout.html', { blobs = blobs }))
end)

router:get('/blobstore/:hash', function(params)
  local data, cursor = bs.get(params.hash)
  app.response:write(template.render('blobstore.html', 'layout.html', { blobs = nil, data = data, hash = params.hash }))
end)

router:get('/filetree', function(params)
  local data = ft.iter_fs()
  app.response:write(template.render('filetree.html', 'layout.html', { data = data }))
end)

router:get('/filetree/versions/:name', function(params)
  local versions = ft.fs_versions(params.name)
  app.response:write(template.render('filetree.html', 'layout.html', { name = params.name, versions = versions }))
end)


router:get('/filetree/:ref/:name/:cref', function(params)
  local node, path = ft.node(params.ref, params.cref)
  if node.name == '_root' then
      node.name = name
  end
  app.response:write(template.render('filetree.html', 'layout.html', { ref = params.ref, name = params.name, node = node, path = path }))
end)

router:get('/filetree/:ref/:name', function(params)
  local root = ft.fs(params.ref)
  root.name = params.name
  app.response:write(template.render('filetree.html', 'layout.html', { ref = params.ref, name = params.name, node = root }))
end)

router:get('/docstore', function(params)
  local collections = docstore.collections()
  app.response:write(template.render('docstore.html', 'layout.html', { collections = collections }))
end)


router:get('/docstore/:col', function(params)
  local schema_name = ''
  local admin_ext = docstore.get_ext(params.col, "admin")
  local schema_ext = docstore.get_ext(params.col, "schema")
  if schema_ext ~= nil then
    schema_name = schema_ext.schema
  end
  local schema = docstore.get_schema(schema_name)
  local col = docstore.col(params.col)
  local cdoc = {}
  local args = app.request:args()

  -- check if a doc ID is requested for edit
  local cid = args:get("_id")
  if cid ~= "" then
    cdoc, _ = col:get(cid)
  end

  -- default search func
  local sf = function(doc) return true end

  -- check if a text search is requested
  local qs = args:get("qs")
  if qs ~= "" then
    -- compute the "text fields" on the fly for the text search
    local tf = {}
    for _, field in ipairs(schema) do
      -- filter the STR|MD type
      if field.field_type == "STR" or field.field_type == "MD" then
        table.insert(tf, field.field_name)
      end
    end
    -- setup the search function
    sf = function(doc) return docstore.text_search(doc, qs, tf) end
  end
  local sort_index = ''
  if admin_ext ~= nil and admin_ext.default_sort_index ~= nil then
    sort_index = admin_ext.default_sort_index
  end
  -- do the query
  -- FIXME(tsileo): no more inline tpl
  local docs, _, cursor, stats  = col:query("", 100, sf, sort_index)
  local jdocs = {}
  for _, d in ipairs(docs) do
    table.insert(jdocs, {doc=d, js=json.encode(d), stats = stats })
  end

  app.response:write(template.render('docstore.html', 'layout.html', { stats = stats, qs = qs, cid = cid, cdoc = cdoc, schema = schema, code = nil, col = params.col, collections = {}, docs = jdocs }))
end)

router:post('/docstore/:col/new', function(params)
  local col = docstore.col(params.col)
  local f = app.request:form()
  local dat = {}
  local schema_name = ''
  local admin_ext = docstore.get_ext(params.col, "admin")
  local schema_ext = docstore.get_ext(params.col, "schema")
  if schema_ext ~= nil then
    schema_name = schema_ext.schema
  end
  local schema = docstore.get_schema(schema_name)
  if schema ~= nil then
    for _, d in ipairs(schema) do
      local v = f:get(d.field_name)
      if f ~= nil then
        dat[d.field_name] = v
      end
    end
  else
    local raw = f:get("raw")
    if raw ~= "" then
      dat = json.decode(raw)
    end
  end

  if app.request:args():get("cid") == "" then
    col:insert(dat)
    app.response:redirect("/api/apps/admin/docstore/" .. params.col)
  else
    col:update(app.request:args():get("cid"), dat) 
    app.response:redirect("/api/apps/admin/docstore/" .. params.col)
  end
end)

router:post('/docstore/:col/remove', function(params)
  local col = docstore.col(params.col)
  col:remove(app.request:args():get("cid")) 
  app.response:redirect("/api/apps/admin/docstore/" .. params.col)
end)

router:post('/docstore/:col', function(params)
  local col = docstore.col(params.col)
  local code = app.request:form():get('code')
  local docs, _, cursor, stats  = col:query("", 100, code)
  local jdocs = {}
  for _, d in ipairs(docs) do
    table.insert(jdocs, {doc=d, js=json.encode(d)})
  end
  app.response:write(template.render('docstore.html', 'layout.html', { stats = stats, code = code, col = params.col, collections = {}, docs = jdocs }))
end)



router:get('/git', function(params)
  local data = {}
  -- TODO(tsileo): support /git/:ns
  for _, ns in ipairs(gs.namespaces()) do
    for _, repo in ipairs(gs.repositories(ns)) do
      table.insert(data, {ns = ns, repo = repo })
    end
  end
  app.response:write(template.render('git_repo.html', 'layout.html', { data = data }))
end)

router:get('/git/:ns/:repo/commit/:hash', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local commit = repo:get_commit(params.hash)
  app.response:write(template.render('git_repo.html', 'layout.html', { name = params.name, ns = params.ns, repo = params.repo, commit = commit }))
end)

router:get('/git/:ns/:repo/log', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local log = repo:log()
  app.response:write(template.render('git_repo.html', 'layout.html', { name = params.name, ns = params.ns, repo = params.repo, log = log }))
end)

router:get('/git/:ns/:repo/file/:hash/:name/plain', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local file = repo:get_file(params.hash)
  local dl = false
  if app.request:args():get("dl") == "1" then
    dl = true
    app.response:headers():set("Content-Disposition", "attachment; filename=" .. params.name)
  end

  if not file.is_binary or dl then
    app.response:write(file.contents)
    return
  end
  return '[binary file, please donwload it]'
end)

router:get('/git/:ns/:repo/file/:hash/:name', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local file = repo:get_file(params.hash)
  app.response:write(template.render('git_repo.html', 'layout.html', { name = params.name, file = file, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/tree/:hash', function(params)
  -- TODO(tsileo): find a way to keep a breadcrumb (of the path in the tree), in the URL, JSON encoded
  local repo = gs.repo(params.ns, params.repo)
  local tree = repo:get_tree(params.hash)
  app.response:write(template.render('git_repo.html', 'layout.html', { tree = tree, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/tree', function(params)
  local repo = gs.repo(params.ns, params.repo)
  local tree = repo:tree()
  app.response:write(template.render('git_repo.html', 'layout.html', { tree = tree, ns = params.ns, repo = params.repo }))
end)

router:get('/git/:ns/:repo/refs', function(params)
  local repo = gs.repo(params.ns, params.repo)
  app.response:write(template.render('git_repo.html', 'layout.html', { ns = params.ns, repo = params.repo, refs = repo:refs() }))
end)

router:get('/git/:ns/:repo', function(params)
  local repo = gs.repo(params.ns, params.repo)
  app.response:write(template.render('git_repo.html', 'layout.html', { host = app.request:host(), scheme = app.request:scheme(), ns = params.ns, repo = params.repo, summary = repo:summary() }))
end)

router:run()
