
//  pumper
//
//  Created by bill donner on 5/7/23.
//
//  Step 1: Pumper executes the script, sending each prompt to the ChatBot and generating a single output file of JSON Challenges which is read by Prepper and, in a later step, by Blender

import Darwin
import Foundation
import ArgumentParser
import q20kshare


let ChatGPTModel = "text-davinci-003"
let ChatGPTURLString = "https://api.openai.com/v1/completions"


var first = true
let encoder = JSONEncoder()
let decoder = JSONDecoder()

func makeChallengeAndWrite(ctx:ChatContext,item:String,jsonOut:FileHandle?) throws {
  // 1. verify we got a proper AIReturns json
  let aireturns = try decoder.decode(AIReturns.self,from:item.data(using:.utf8)!)
  // 2. make a Challenge from the stuff from AI - generates UUID for challenge block
  let challenge:Challenge = aireturns.toChallenge(source:ChatGPTModel,prompt:ctx.prompt)
  // 3. write JSON to file
  if let fileHandle = jsonOut {
    // append response with prepended comma if we need one
    if !first {
      fileHandle.write(",".data(using: .utf8)!)
    } else {
      first = false
    }
    // 4. encode Challenge as JSON and write that out
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(challenge)
    let str = String(data:data,encoding: .utf8)
    if let str = str {
      fileHandle.write(str.data(using: .utf8)!)
    }
  }
}

struct Pumper: ParsableCommand {
  
  //  Step 1: Pumper executes the script, sending each prompt to the ChatBot and generating a single output file of JSON Challenges which is read by Prepper and, in a later step, by Blender
  
  static let configuration = CommandConfiguration(
    abstract: "Step 1: Pumper executes the script, sending each prompt to the ChatBot and generating a single output file of JSON Challenges which is read by Prepper and, in a later step, by Blender.",
    version: "0.3.3",
    subcommands: [],
    defaultSubcommand: nil,
    helpNames: [.long, .short]
  )
  
  @Argument(help: "Input text script file (Between_0_1.txt)")
  var input: String
  
  @Argument( help:"Output json file (Between_1_2.json)")
  var output: String
  
  @Option(name: .long, help: "How many prompts to execute")
  var max: Int = 65535
  
  @Option(name: .long, help: "Execute the script once Only")
  var once: Bool = true
  
  @Option(name: .long, help: "Print dots whilst awaiting AI")
  var dots: Bool = false
  
  @Option(name: .long, help: "Print a lot more")
  var verbose: Bool = false
  
  @Option(name: .long , help: "Generate Unique File Names")
  var unique : Bool = true
  
  @Option(name: .long, help: "Don't call AI")
  var dontcall: Bool = false
  
  @Option(name:.long,help: "The pattern to use to split the file")
  var split_pattern: String = "***"
  
  @Option(name:.long,help: "The pattern to use to indicate a comments line")
  var comments_pattern: String = "///"
  
  @available(iOS 16.0, *)
  mutating func run() throws {
    print(">Pumper Command Line: \(CommandLine.arguments)")
    print(">Pumper is STEP1 running at \(Date())")
    var apiKey = ""
    do {
      apiKey = try getAPIKey()
      print(">Pumper Using apikey: " + apiKey)
    }
    catch {
      print("Cannot access APIKEY -- \(error.localizedDescription)")
      fatalError("Cannot access APIKEY -- \(error.localizedDescription)")
    }
    guard let apiurl = URL(string: ChatGPTURLString) else {
      fatalError("Invalid API URL")
    }
    guard let outURL = URL(string:output) else {
      fatalError("Invalid Output URL")
    }
    // setup the context block which will maintain the connection with the AI
    let ctx = ChatContext(max: max, apiKey: apiKey, apiURL: apiurl, outURL: outURL, model:ChatGPTModel, verbose:verbose, dots:dots,dontcall:dontcall,comments_pattern:comments_pattern,split_pattern:split_pattern, style:.promptor)
    
    guard let url = URL(string:input) else {  print ("bad url"); return  }
    let contents = try String(contentsOf: url)
    let templates = contents.split(separator: split_pattern)
      .map{$0.trimmingCharacters(in: .whitespacesAndNewlines)}
    if  verbose {
      print(">Prompts url: \(url)  (\(contents.count) bytes, \(templates.count) templates)")
      print(">Contacting: \(ChatGPTURLString)")
    }
    
    let jsonOutHandle = try prepOutputChannels(ctx:ctx)
    
    
    do {
      if let jsonOutHandle = jsonOutHandle {
        
        // all set up and get to work
        try pumpItUp(ctx:ctx,templates:templates, jsonOut: jsonOutHandle, justOnce:once, cleaner: {s in
          extractSubstringsInBrackets(input: "{ "  + s)
        },itemHandler: { x,y,z in
          try  makeChallengeAndWrite(ctx:x,item:y,jsonOut:z)
          
        })
      }
    }
    catch {
      if error as? PumpingErrors == PumpingErrors.reachedMaxLimit {
        print("\n>Pumper reached max limit of \(ctx.max) prompts sent to the AI")
      }
      else
      if error as? PumpingErrors == PumpingErrors.reachedEndOfScript {
        print("\n>Pumper reached end of input script \(ctx.pumpCount) prompts sent to the AI")
      }
      else {
        print ("Pumper error: \(error)")
      }
    }
//    if ctx.pumpCount < ctx.max  {
//      RunLoop.current.run() // suggested by fivestars blog
//    }
    print(">Pumper Exiting Normally - Pumped:\(ctx.pumpCount)" + " Bad Json: \( ctx.badJsonCount)" + " Network Issues: \(ctx.networkGlitches)\n")
  }// otherwise we should exit
}

Pumper.main()
