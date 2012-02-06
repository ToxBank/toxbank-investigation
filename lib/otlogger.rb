class OTLogger < Logger
  
  def pwd
    path = Dir.pwd.to_s
    index = path.rindex(/\//)
    return path if index==nil
    path[(index+1)..-1]
  end
  
  def trace()
    lines = caller(0)
    n = 2
    line = lines[n]
    
    while (line =~ /spork.rb/ or line =~ /create/ or line =~ /overwrite.rb/)
      n += 1
      line = lines[n]
    end
  
    index = line.rindex(/\/.*\.rb/)
    return line if index==nil
    line[index..-1]
  end
  
  def format(msg)
    pwd.ljust(18)+" :: "+msg.to_s+"           :: "+trace
  end
  
  def debug(msg)
    super format(msg)
  end
  
  def info(msg)
    super format(msg)
  end
  
  def warn(msg)
    super format(msg)
  end

  def error(msg)
    super format(msg)
  end

end
