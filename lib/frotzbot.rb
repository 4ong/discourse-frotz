module DiscourseFrotz

  class FrotzBot < StandardError; end

  class FrotzBot

    def self.strip_header_and_footer(string, show_intro, story_header_lines, story_load_lines, story_save_lines)

      lines = string.split(/\n+|\r+/)

      if show_intro
        lines.delete_at(0)
        lines.delete_at(0)
      end
  
      stripped_lines = []
  
      lines.each_with_index do |line, index|
        line = line.sub("> > ", "")
        if line.strip[0,1] == "@"
          next
        end
  
        if (index < story_header_lines-1)
          if show_intro
            stripped_lines << line.gsub("\"", "'")
          end
        elsif (index < (story_header_lines+story_load_lines-1))
          #
          # Skip the load data
          #
        elsif (!show_intro && ((index + story_save_lines) >= (lines.count+1)))
          #
          # Skip the save data
          #
        elsif (!show_intro)
          stripped_lines << line.gsub("\"", "'")
        end
      end
  
      return stripped_lines.join("\n")
    end

    def self.list_games

      game_settings = SiteSetting.frotz_stories.split('|')
      games_list = ""
      
      game_settings.each_with_index do |line, index|
        game = line.split(',')
        games_list +="#{index+1}. #{game[0]}\n"
      end

      games_list
    end

    def self.ask(opts)
  
      frotz_response = ""
      save_location = ""
      new_save_location = ""
      game_file = ""
      story_header_lines = 9
      story_load_lines = 7
      story_save_lines = 3
      game_file_prefix = ""
      game_title = ""
      supplemental_info = ""
      game_number = 1
      overwrite = ""
      input_data = ""

      msg = opts[:message_body].downcase

      user_id = opts[:user_id]

      available_games = list_games

      msg = CGI.unescapeHTML(msg.gsub(/[^a-zA-Z0-9 ]+/, "")).gsub(/[^A-Za-z0-9]/, " ").strip

      current_users_save_files = `ls -t #{SiteSetting.frotz_saves_directory}/*_#{user_id}.zsav`
      
      executable_check = `ls -t #{SiteSetting.frotz_dumb_executable_directory}/dfrotz`

      if executable_check.blank?
        return I18n.t('frotz.errors.noexecutable')
      end 

      save_location = Pathname(current_users_save_files.split("\n").first.blank? ? "" : current_users_save_files.split("\n").first)
      
      if save_location
        first_filename = save_location.basename.to_s
        if first_filename.include?('_')
          current_game_file_prefix = first_filename.split('_')[0]

          available_games = SiteSetting.frotz_stories.split('|')

          available_games.each_with_index do |line, index|
              game = line.split(',')
              story_file = game[1]

              if story_file.include?(current_game_file_prefix)
                game_number = index + 1
                game_file = story_file
                story_header_lines = game[2].to_i
                story_load_lines = game[3].to_i
                story_save_lines = game[4].to_i
              end
          end
        end
      end
     
      if ['save','restore','quit','exit'].include?(msg)
          return "'#{msg}' #{I18n.t('frotz.errors.restricted')}"
      end

      if ['reset game'].include?(msg)
        if current_users_save_files.length
          `rm #{save_location}`
          supplemental_info = "**Game Reset:**\n\n"
          msg = "start game #{game_number}"
        else
          return I18n.t('frotz.errors.nosavefile')
        end
      end

      if msg.include?('list games')
        return list_games
      end

      if msg.include?('continue game') || msg.include?('start game')
        if !msg[/\d+/].nil?
          game_index = msg[/\d+/].to_i - 1

          available_games = SiteSetting.frotz_stories.split('|')

          if !game_index.between?(0, available_games.count - 1)
            return I18n.t('frotz.errors.invalidgamenumber')
          end

          available_games.each_with_index do |line, index|
          
            if index == game_index
              game = line.split(',')
              game_title = game[0]
              game_file = game[1]
              story_header_lines = game[2].to_i
              story_load_lines = game[3].to_i
              story_save_lines = game[4].to_i
              supplemental_info = "**#{I18n.t('frotz.responses.starting')} #{game_title}:**\n\n"
              save_location = ""
              new_save_location = Pathname("#{SiteSetting.frotz_saves_directory}/#{game_file.split('.')[0]}_#{user_id}.zsav")
            end
          end
          
          if msg.include?('continue game')

            found_save = false
            
            available_saves = current_users_save_files.split("\n")

            available_saves.each_with_index do |save, index|
            
              if Pathname(save).basename.to_s.include?(game_file.split(".")[0])
                save_location = Pathname(save)
                new_save_location = Pathname(save)
                found_save = true
              end
            end

            if !found_save
              save_location = ""
            end
            supplemental_info = "**#{I18n.t('frotz.responses.continuing')} #{game_title}:**\n\n"
            msg = "look"
          end
        else
          return I18n.t('frotz.errors.gamenotspecified')
        end
      end

      if game_file.blank?
        return I18n.t('frotz.errors.gamenotspecified')
      end

      if save_location.blank?
        story_load_lines = 0
      else
        input_data = "restore\n#{save_location}\n"
        if new_save_location.blank?
          new_save_location = save_location
        end
      end 

      # Restore from saved path
      # \lt - Turn on line identification
      # \cm - Dont show blank lines
      # \w  - Advance the timer to now
      # Command
      # Save to save path - override Y, if file exists

      overwrite = "\ny"

      story_path_check = `ls -t #{SiteSetting.frotz_story_files_directory}/#{game_file}`

      if story_path_check.blank?
        return I18n.t('frotz.errors.nostoryfile')
      end 

      story_path = Pathname("#{SiteSetting.frotz_story_files_directory}/#{game_file}")

      input_data += "\\lt\n\\cm\\w\n#{msg}\nsave\n#{new_save_location}#{overwrite}\n"

      input_stream = Pathname("#{SiteSetting.frotz_stream_files_directory}/#{user_id}.f_in")
      
      File.open(input_stream, 'w+') { |file| file.write(input_data) }

      output = `#{SiteSetting.frotz_dumb_executable_directory}/./dfrotz -i -Z 0 #{story_path} < #{input_stream}`
      
      puts "BEFORE strip:\n"+output
      lines = strip_header_and_footer(output, save_location.blank?, story_header_lines, story_load_lines, story_save_lines) 
      puts "AFTER strip:\n"+lines
      
      reply = supplemental_info + lines
    end
  end
end