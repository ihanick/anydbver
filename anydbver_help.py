def arg_help(name):
  all_subargs = {
      "percona-server": "percona-server:ver,docker-image,mysql-router,master=NODE,leader=NODE"
      }
  examples = {
      "percona-server": "anydbver deploy ps:5.7.35 node1 ps:5.7.35,master=node0"
      }
  if name in all_subargs and name in examples:
    return "R|{}\nEx. {}".format(all_subargs[name], examples[name])
  elif name in examples:
    return "R|Ex. {}".format(examples[name])
  elif name in examples:
    return "R|{}".format(all_subargs[name])
  return ""
