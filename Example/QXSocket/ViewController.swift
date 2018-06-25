//
//  ViewController.swift
//  QXSocket
//
//  Created by 905799827@qq.com on 06/11/2018.
//  Copyright (c) 2018 905799827@qq.com. All rights reserved.
//

import UIKit
import QXSocket

class ViewController: UIViewController {

    var m : QXTCPSocketManager?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        self.m = QXTCPSocketManager.manager(host: "127.0.0.1", on: 6000)
        
        m?.connect()
        
        m?.delegate = self
    }

    @IBOutlet weak var textInput: UITextField!
    
    @IBAction func sendButton(_ sender: Any) {
        
        m?.send(data: (textInput.text?.data(using: String.Encoding.utf8))!)
        
    }
    
    @IBOutlet weak var receiver: UILabel!
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

extension ViewController : QXSocketManagerProtocol {
    func qx_socketDidReceiveData(_ data: Data) {
        DispatchQueue.main.async {
            self.receiver.text = String(data: data, encoding: .utf8)
        }
        
    }
}

