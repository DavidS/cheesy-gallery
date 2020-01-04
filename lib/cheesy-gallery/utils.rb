# frozen_string_literal: true

# This Page subclass can be used to create new pages in the target site from scratch
class CheesyGallery:: PageWithoutAFile < Jekyll::Page
  def read_yaml(*)
    @data ||= {} # this is the correct side-effect of this method # rubocop:disable Naming/MemoizedInstanceVariableName
  end
end
