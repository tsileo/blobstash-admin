local template = require('template')
local router = require('router').new()
local gs = require('gitserver')

router:get('/git', function(params)
  local data = {}
  for _, ns in ipairs(gs.namespaces()) do
    for _, repo in ipairs(gs.repositories(ns)) do
      table.insert(data, {ns = ns, repo = repo })
    end
  end

  app.response:write(template.render('index.html', { data = data }))
end)

router:get('/git/:ns/:repo', function(params)
  local repo = gs.repo(params.ns, params.repo)
  app.response:write(template.render('git_repo.html', { ns = params.ns, repo = params.repo, summary = repo:summary() }))
end)

router:run()
