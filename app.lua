local template = require('template')
local extra = require('extra')
local json = require('json')
local router = require('router').new()
local kvs = require('kvstore')
local ft = require('filetree')
local bs = require('blobstore')
local docstore = require('docstore')
local apps = require('apps')
local _blobstash = require('_blobstash')
local user_agent = "Admin UI"

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
  app.response:write(template.render('filetree.html', 'layout.html', { data = data, is_index = true }))
end)

router:post('/filetree', function(params)
  local form = app.request:form()
  ft.create_fs(form:get('name'))
  local data = ft.iter_fs()
  app.response:write(template.render('filetree.html', 'layout.html', { data = data, is_index = true }))

end)

router:get('/filetree/versions/:name', function(params)
  local versions = ft.fs_versions(params.name)
  app.response:write(template.render('filetree.html', 'layout.html', { name = params.name, versions = versions }))
end)

router:get('/filetree/:ref/:name/:cref', function(params)
  local node, path, spath = ft.node(params.ref, params.cref)
  if node.name == '_root' then
      node.name = name
  end
  app.response:write(template.render('filetree.html', 'layout.html', { ref = params.ref, name = params.name, node = node, path = path, spath = spath }))
end)

router:get('/filetree/:ref/:name', function(params)
  local root = ft.fs(params.ref)
  root.name = params.name
  app.response:write(template.render('filetree.html', 'layout.html', { ref = params.ref, name = params.name, node = root, spath = "/"  }))
end)

router:post('/filetree/upload', function (params)
  local f = app.request:file('file')
  local form = app.request:args()
  local ref = form:get('ref')
  local name = form:get('name')
  local path = form:get('path')
  local new_parent, _ = ft.put_file_at({user_agent = user_agent, message = "Uploaded " .. f.filename .. " from the admin UI"}, f.filename, f.contents, name, path)
  if path == "/" then
    app.response:redirect("/api/apps/admin/filetree/" .. new_parent .. "/" .. name) --  .. "/" .. new_cref.ref)

  else
    local new_root = ft.fs_by_name(name)
    app.response:redirect("/api/apps/admin/filetree/" .. new_root.hash .. "/" .. name  .. "/" .. new_parent)
  end
  --app.response:write(template.render('filetree.html', 'layout.html', { ref = params.ref, name = params.name, node = root }))
end)

router:post('/filetree/mkdir', function (params)
  local f = app.request:form()
  local newdir = f:get('newdir')
  local args = app.request:args()
  local ref = args:get('ref')
  local name = args:get('name')
  local path = args:get('path')
  local newref = ft.mkdir(name, path, newdir)
  local new_root = ft.fs_by_name(name)
  app.response:redirect("/api/apps/admin/filetree/" .. new_root.hash .. "/" .. name .. "/" .. newref)
end)


router:get('/docstore', function(params)
  local collections = docstore.collections()
  app.response:write(template.render('docstore.html', 'layout.html', { collections = collections }))
end)

router:get('/docstore/:col', function(params)
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
  -- sf = function(doc) return docstore.text_search(doc, qs, tf) end
  local sort_index = ''
  if admin_ext ~= nil and admin_ext.default_sort_index ~= nil then
    sort_index = admin_ext.default_sort_index
  end
  -- do the query
  -- FIXME(tsileo): no more inline tpl
  local docs, pointers, cursor, stats  = col:query(args:get("cursor"), 100, sf, sort_index)
  local jdocs = {}
  for _, d in ipairs(docs) do
    table.insert(jdocs, {doc=d, js=json.encode(d), stats = stats })
  end

  app.response:write(template.render('docstore.html', 'layout.html', { stats = stats, qs = qs, cid = cid, cdoc = cdoc, code = nil, col = params.col, collections = {}, docs = jdocs }))
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

router:run()
