require 'yaml'


LIB_NAMES = {
  'decode' => {
    'lunajson' => "lunajson decoder",
    'lunajson_sax' => "lunajson SAX",
    'dkjson_lpeg' => "dkjson with lpeg",
    'dkjson_pure' => "dkjson w/o lpeg",
    'cjson' => "Lua CJSON",
  },
  'encode' => {
    'lunajson' => "lunajson",
    'dkjson' => "dkjson",
    'cjson' => "Lua CJSON",
  },
}


def create_result()
  Hash.new {|h, k| h[k] = create_result }
end
result = create_result


YAML.load_stream(ARGF).each do |data|
  lua_impl = data['lua_impl']
  ops = ['decode', 'encode']
  ops.each do |op|
    data[op].each do |lib, r|
      lib = LIB_NAMES[op][lib]
      r.each do |task, time|
        task = "#{op}-#{task}"
        result[task][lua_impl][lib] = time
      end
    end
  end
end


result.each do |task, frame|
  File.open("#{task}.dat", 'w') {|f|
    first = true
    frame.each do |lua_impl, row|
      f.puts ([""] + row.keys).map(&:inspect).join(' ') if first
      first = false
      f.puts ([lua_impl] + row.values).map(&:inspect).join(' ')
    end
  }
end
