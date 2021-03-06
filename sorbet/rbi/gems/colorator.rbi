# This file is autogenerated. Do not edit it by hand. Regenerate it with:
#   srb rbi gems

# typed: strict
#
# If you would like to make changes to this file, great! Please create the gem's shim here:
#
#   https://github.com/sorbet/sorbet-typed/new/master?filename=lib/colorator/all/colorator.rbi
#
# colorator-1.1.0

class String
  def ansi_jump(*args); end
  def black(*args); end
  def blue(*args); end
  def bold(*args); end
  def clear_line(*args); end
  def clear_screen(*args); end
  def colorize(*args); end
  def cyan(*args); end
  def green(*args); end
  def has_ansi?(*args); end
  def has_color?(*args); end
  def magenta(*args); end
  def red(*args); end
  def reset_ansi(*args); end
  def reset_color(*args); end
  def strip_ansi(*args); end
  def strip_color(*args); end
  def white(*args); end
  def yellow(*args); end
end
module Colorator
  def ansi_jump(str, num); end
  def clear_line(str = nil); end
  def clear_screen(str = nil); end
  def colorize(str = nil, color); end
  def has_ansi?(str); end
  def reset_ansi(str = nil); end
  def self.ansi_jump(str, num); end
  def self.black(str); end
  def self.blue(str); end
  def self.bold(str); end
  def self.clear_line(str = nil); end
  def self.clear_screen(str = nil); end
  def self.colorize(str = nil, color); end
  def self.cyan(str); end
  def self.green(str); end
  def self.has_ansi?(str); end
  def self.has_color?(str); end
  def self.magenta(str); end
  def self.red(str); end
  def self.reset_ansi(str = nil); end
  def self.reset_color(str = nil); end
  def self.strip_ansi(str); end
  def self.strip_color(str); end
  def self.white(str); end
  def self.yellow(str); end
  def strip_ansi(str); end
end
