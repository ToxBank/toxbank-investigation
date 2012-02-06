module OpenTox
  require "rexml/document"

  #Module for policy-processing 
  # @see also http://www.opentox.org/dev/apis/api-1.2/AA for opentox API specs
  # Class Policies corresponds to <policies> container of an xml-policy-fle
  class Policies 
  
    attr_accessor :name, :policies
    
    def initialize()
      @policies = {}
    end
    
    #create new policy instance with name
    # @param [String]name of the policy
    def new_policy(name)
      @policies[name] = Policy.new(name)
    end
    
    #drop a specific policy in a policies instance
    # @param [String]name of the policy
    # @return [Boolean]
    def drop_policy(name)
      return true if @policies.delete(name) 
    end

    #drop all policies in a policies instance
    def drop_policies
      @policies.each do |name, policy|
        drop_policy(name)
      end
      return true
    end
    
    # @return [Array] set of arrays affected by policies
    def uris
      @policies.collect{ |k,v| v.uris }.flatten.uniq
    end

        #drop all policies in a policies instance
    def names
      out = []
      @policies.each do |name, policy|
        out << name 
      end
      return out
    end

    #loads a default policy template in policies instance
    def load_default_policy(user, uri, group="member")    
      template = case user
        when "guest", "anonymous" then "default_guest_policy"
        else "default_policy"     
      end
      xml = File.read(File.join(File.dirname(__FILE__), "templates/#{template}.xml"))
      self.load_xml(xml)
      datestring = Time.now.strftime("%Y-%m-%d-%H-%M-%S-x") + rand(1000).to_s
       
      @policies["policy_user"].name = "policy_user_#{user}_#{datestring}"
      @policies["policy_user"].rules["rule_user"].uri = uri
      @policies["policy_user"].rules["rule_user"].name = "rule_user_#{user}_#{datestring}"
      @policies["policy_user"].subjects["subject_user"].name = "subject_user_#{user}_#{datestring}"
      @policies["policy_user"].subjects["subject_user"].value = "uid=#{user},ou=people,dc=opentox,dc=org"
      @policies["policy_user"].subject_group = "subjects_user_#{user}_#{datestring}"
            
      @policies["policy_group"].name = "policy_group_#{group}_#{datestring}" 
      @policies["policy_group"].rules["rule_group"].uri = uri
      @policies["policy_group"].rules["rule_group"].name = "rule_group_#{group}_#{datestring}"
      @policies["policy_group"].subjects["subject_group"].name = "subject_group_#{group}_#{datestring}"
      @policies["policy_group"].subjects["subject_group"].value = "cn=#{group},ou=groups,dc=opentox,dc=org"
      @policies["policy_group"].subject_group = "subjects_#{group}_#{datestring}" 
      return true
    end    

    #loads a xml template    
    def load_xml(xml)
      rexml = REXML::Document.new(xml)
      rexml.elements.each("Policies/Policy") do |pol|    #Policies
        policy_name = pol.attributes["name"]
        new_policy(policy_name)
        #@policies[policy_name] = Policy.new(policy_name)      
        rexml.elements.each("Policies/Policy[@name='#{policy_name}']/Rule") do |r|    #Rules
          rule_name = r.attributes["name"]        
          uri = rexml.elements["Policies/Policy[@name='#{policy_name}']/Rule[@name='#{rule_name}']/ResourceName"].attributes["name"]
          @policies[policy_name].rules[rule_name] = @policies[policy_name].new_rule(rule_name, uri)
          rexml.elements.each("Policies/Policy[@name='#{policy_name}']/Rule[@name='#{rule_name}']/AttributeValuePair") do |attribute_pairs|
            action=nil; value=nil;
            attribute_pairs.each_element do |elem|
              action = elem.attributes["name"] if elem.attributes["name"]
              value = elem.text if elem.text
            end
            if action and value
              case action
              when "GET"
                @policies[policy_name].rules[rule_name].get    = value
              when "POST"
                @policies[policy_name].rules[rule_name].post   = value
              when "PUT"
                @policies[policy_name].rules[rule_name].put    = value
              when "DELETE"    
                @policies[policy_name].rules[rule_name].delete = value
              end
            end
          end        
        end
        rexml.elements.each("Policies/Policy[@name='#{policy_name}']/Subjects") do |subjects|    #Subjects
          @policies[policy_name].subject_group = subjects.attributes["name"]        
          rexml.elements.each("Policies/Policy[@name='#{policy_name}']/Subjects[@name='#{@policies[policy_name].subject_group}']/Subject") do |s|    #Subject
            subject_name  = s.attributes["name"]
            subject_type  = s.attributes["type"]
            subject_value = rexml.elements["Policies/Policy[@name='#{policy_name}']/Subjects[@name='#{@policies[policy_name].subject_group}']/Subject[@name='#{subject_name}']/AttributeValuePair/Value"].text
            @policies[policy_name].new_subject(subject_name, subject_type, subject_value) if subject_name and subject_type and subject_value
          end
        end      
      end    
    end
    
    #generates xml from policies instance
    def to_xml
      doc = REXML::Document.new()
      doc <<  REXML::DocType.new("Policies", "PUBLIC  \"-//Sun Java System Access Manager7.1 2006Q3\n Admin CLI DTD//EN\" \"jar://com/sun/identity/policy/policyAdmin.dtd\"")
      doc.add_element(REXML::Element.new("Policies"))
      
      @policies.each do |name, pol|
        policy = REXML::Element.new("Policy")
        policy.attributes["name"] = pol.name
        policy.attributes["referralPolicy"] = false
        policy.attributes["active"] = true
        @policies[name].rules.each do |r,rl|
          rule = @policies[name].rules[r]
          out_rule = REXML::Element.new("Rule")
          out_rule.attributes["name"] = rule.name
          servicename = REXML::Element.new("ServiceName")
          servicename.attributes["name"]="iPlanetAMWebAgentService"
          out_rule.add_element(servicename)
          rescourcename = REXML::Element.new("ResourceName")
          rescourcename.attributes["name"] = rule.uri
          out_rule.add_element(rescourcename)
          
          ["get","post","delete","put"].each do |act|
            if rule.method(act).call
              attribute = REXML::Element.new("Attribute") 
              attribute.attributes["name"] = act.upcase
              attributevaluepair = REXML::Element.new("AttributeValuePair")
              attributevaluepair.add_element(attribute)
              attributevalue = REXML::Element.new("Value")
              attributevaluepair.add_element(attributevalue)
              attributevalue.add_text REXML::Text.new(rule.method(act).call)
              out_rule.add_element(attributevaluepair)
              
            end
          end
          policy.add_element(out_rule)
        end      

        subjects = REXML::Element.new("Subjects")
        subjects.attributes["name"] = pol.subject_group
        subjects.attributes["description"] = ""
        @policies[name].subjects.each do |subj, subjs|
          subject = REXML::Element.new("Subject")
          subject.attributes["name"] = pol.subjects[subj].name
          subject.attributes["type"] = pol.subjects[subj].type
          subject.attributes["includeType"] = "inclusive"
          attributevaluepair = REXML::Element.new("AttributeValuePair")
          attribute = REXML::Element.new("Attribute") 
          attribute.attributes["name"] = "Values"
          attributevaluepair.add_element(attribute)
          attributevalue = REXML::Element.new("Value")
          attributevalue.add_text REXML::Text.new(pol.subjects[subj].value)
          attributevaluepair.add_element(attributevalue)
          subject.add_element(attributevaluepair)
          subjects.add_element(subject)
        end
        policy.add_element(subjects)
        doc.root.add_element(policy)
      end    
      out = ""
      doc.write(out, 2)
      return out
    end  
    
  end
  
  #single policy in a policies instance
  class Policy 
  
    attr_accessor :name, :rules, :subject_group, :subjects
  
    def initialize(name)
      @name = name
      @rules = {}
      @subject_group = ""
      @subjects = {}
    end
    
    #create a new rule instance for the policy
    def new_rule(name, uri)
      @rules[name] = Rule.new(name, uri)
    end
    
    #create a new subject instance for the policy 
    def new_subject(name, type, value)
      @subjects[name] = Subject.new(name, type, value)
    end
    
    # @return [Array] set of uris affected by policy
    def uris
      @rules.collect{ |k,v| v.uri }.uniq
    end
    
    #rule inside a policy
    class Rule
      
      attr_accessor :name, :uri, :get, :post, :put, :delete
      
      def initialize(name, uri)
        @name = name
        @uri = uri
      end
      
      def rename(new, old)
        self[new] = self.delete(old)
        self[new].name = new
      end
      
      def get=(value)
        @get = check_value(value, @get)
      end
    
      def post=(value)
        @post = check_value(value, @post)
      end
          
      def delete=(value)
        @delete = check_value(value, @delete)
      end
      
      def put=(value)
        @put = check_value(value, @put)
      end
          
      private
      #checks if value is allow or deny. returns old value if not valid. 
      def check_value(new_value, old_value)
        return (new_value=="allow" || new_value=="deny" || new_value==nil) ? new_value : old_value 
      end
    end
    
    class Subject

      attr_accessor :name, :type, :value  

      def initialize(name, type, value)
        @name  = name
        @type  = type
        @value = value
      end
    end
  end
end