-- converts numeric part of the table {1 = a, 2 = b, 3 = c} to set 
-- set it's a table with {a = true, b = true, c = true e.t.c}

function get_set(table)
  local set = {}
  for k, v in pairs(table) do
    set[v] = true
  end
  return set
end


function set_eq(s1, s2)
  local acc = true
  local s2i, s2v = next(s2, nil)
  for k, _ in pairs(s1) do
      acc = acc and s2[k] ~= nil and s2v
      s2i, s2v = next(s2, s2i)
  end
  return acc and (not s2v)
end


function set_union(s1, s2)
  for k, _ in pairs(s2) do
    s1[k] = true
  end
end

function print_info(object, prefix, n)
  if n == 0 then return end
  for k, v in pairs(object) do
    print(prefix .. k .. " = " .. tostring(v))
    if (type(v) == 'table') then
      print_info(v, prefix .. "\t", n - 1)
    end
  end
end


function criteria_eq(c1, c2)
  if c1 == nil or c2 == nil then return true end
  return set_eq(get_set(c1), get_set(c2))
end


-- given a = {1, 2, 3} b = {4, 5, 6}
-- makes a = {1, 2, 3, 4, 5, 6} b = {4, 5, 6}
function table.append(t1, t2)
  for i, v in ipairs(t2) do
    table.insert(t1, v)
  end
end

-- given a = {1, 2, 3} b = {4, 5, 6}
-- makes a = {1, 2, 3, 4, 5, 6} b = {}
function table.push(t1, t2)
  table.append(t1, t2)
  for k, _ in pairs(t2) do
    t2[k] = nil
  end
end

-- remove duplicates from a table
--
function table.to_set(t)
  local s = get_set(t)
  local x = {}  
  for k, _ in pairs(s) do
    table.insert(x, k)
  end
  return x
end


-- collects dependency graph as a flat list
--
function flatten(cfg, prj, acc)
  for _, s in ipairs(prj.sib) do
    table.insert(acc, s)
    flatten(cfg, cfg[s], acc)
  end
end

-- return duplicates in a table as a set
-- 
function get_duplicates(ft)
  local keys = {}
  local dups = {}
  for _, k in pairs(ft) do
    if keys[k] then
      dups[k] = true
    end
    keys[k] = true
  end
  return dups
end

-- suppose we have main.exe > [a.lib] and a.lib > [b.lib, c.lib]
-- compose "on" means [a.lib, b.lib, c.lib] archived in a single a.lib
-- compose "off" means [b.lib, c.lib] passed to main.exe linker
-- by default it's "off" for static libs and "on" for executables
premake.api.register {
  name = "compose",
  scope = "project",
  kind = "boolean",
}

-- this function propagates unoccluded dependecies from siblings to root 
--
function transitive_run(pcache, item)
  if item.up == nil then
    item.up = {sys = {}, sib = {}}
    if item.kind == "StaticLib" then
    -- static libs pass system dependencies up to root
    -- because they are composed by archiver not linker
      table.push(item.up.sys, item.sys)
      if not item.ar then
        -- siblings can be consumed depending on compose flag
        table.push(item.up.sib, item.sib)
      end
      for _, k in pairs(item.sib) do
        local up = transitive_run(pcache, pcache[k])
        table.append(item.up.sys , up.sys)
        table.append(item.ar and item.sib or item.up.sib, up.sib)
      end
    else
      -- shared libraries and executables consume their dependecies
      for _, k in pairs(item.sib) do
        local up = transitive_run(pcache, pcache[k])
        table.append(item.sys , up.sys)
        table.append(item.sib, up.sib)
      end
    end
  end
  return item.up
end


function check_diamonds(cfg)
  local acc = {}
  for _, prj in pairs(cfg) do
    set_union(acc, get_set(prj.sib))
  end
  for k, prj in pairs(cfg) do
    if not acc[k] then
      local ft = {}
      flatten(cfg, prj, ft)
      for d, _ in pairs(get_duplicates(ft)) do
        print("Detected multiple inclusion of " .. d .. " in " .. k)
      end
    end
  end
end


act = premake.action._list[_ACTION]
act.saved_onWorkspace = act.onWorkspace
pm = premake

-- this is relative path of the project
--
function getprojectpath(cfg)
  local fp = pm.config.gettargetinfo(cfg).fullpath
  return pm.project.getrelative(cfg.project, fp)
end

-- with this function we can get different 
-- parts of the target file path
--
function transform_names(names, kind)
  local ret = {}  
  local map = {
    name = path.getname,
    basename = path.getbasename,
    directory = path.getdirectory,
  }
  for _, name in ipairs(names) do
    if map[kind] ~= nil then
      table.insert(ret, map[kind](name))
    else
      table.insert(ret, name)
    end
  end
  return ret
end


-- this is injection in existing toolchain
-- order of inclusion matters, use e.g...
-- require "ninja"
-- require "transitive"
-- or just
-- require "transitive"
-- if you use standard gmake2 or msvc

act.onWorkspace = function(ws)
  print("Transitive pass...")
  local dg = {}
  for p in pm.workspace.eachproject(ws) do
    -- collection of related information
    for cfg in pm.project.eachconfig(p) do
      local pth = getprojectpath(cfg)
      local sys = pm.config.getlinks(cfg, "system", "basename")
      local sib = pm.config.getlinks(cfg, "siblings", "fullpath")
      if not dg[cfg.buildcfg] then
        dg[cfg.buildcfg] = {}
      end
      local ar = cfg.compose == nil or cfg.compose
      dg[cfg.buildcfg][pth] = {kind = cfg.kind, sys = sys, sib = sib, ar = ar}
    end
  end
  -- transitive propagation of the dependency graph
  for _, cfg in pairs(dg) do
    for _, prj in pairs(cfg) do
      transitive_run(cfg, prj)
      prj.sys = table.to_set(prj.sys)
      prj.sib = table.to_set(prj.sib)
    end
    check_diamonds(cfg)
  end
  
  -- this is another hack
  -- instead of changing configuration data directly
  -- we respond dynamically from our cache
  -- 
  local saved_getlinks = pm.config.getlinks
  pm.config.getlinks = function (c, k, p, l)
    local ret = {}
    local pth = getprojectpath(c)
    local prj = dg[c.buildcfg][pth]
    
    if k == "siblings" or k == "all" then
      table.append(ret, prj.sib)
    end
    if k == "system" or k == "all" then
      table.append(ret, prj.sys)
    end
    return table.to_set(transform_names(ret, p))
  end
  
  act.saved_onWorkspace(ws)
end
